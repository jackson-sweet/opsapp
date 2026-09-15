import Foundation
import SwiftData
import Supabase

enum SiteVisitVersionedSync {
    typealias Deliver = (UUID, SiteVisitWriteCommand, String) async throws -> SiteVisitWriteReceipt
    /// (original command id, command, resolution, expected actor, use choice protocol)
    typealias DeliverResolution = (UUID, SiteVisitWriteCommand, SiteVisitWriteResolution, String, Bool) async throws -> SiteVisitWriteReceipt
    static func handles(_ operation: SyncOperation) -> Bool {
        operation.entityType == SyncEntityType.siteVisitType.rawValue ||
            operation.entityType == SyncEntityType.siteVisitChecklistAnswer.rawValue
    }
    static func command(_ operation: SyncOperation) -> SiteVisitWriteCommand? {
        if operation.entityType == SyncEntityType.siteVisitType.rawValue {
            return try? JSONDecoder().decode(SiteVisitWriteCommand.self, from: operation.payload)
        }
        return (try? JSONDecoder().decode(SiteVisitSyncOperation.Payload.self, from: operation.payload))?.writeCommand
    }
    static func setCommand(_ command: SiteVisitWriteCommand, on operation: SyncOperation) throws {
        guard operation.siteVisitWriteAttemptedAt == nil else { throw SiteVisitWriteError.invalidReceipt }
        if operation.entityType == SyncEntityType.siteVisitType.rawValue {
            operation.payload = try JSONEncoder().encode(command)
        } else {
            let previous = try JSONDecoder().decode(SiteVisitSyncOperation.Payload.self, from: operation.payload)
            operation.payload = try JSONEncoder().encode(SiteVisitSyncOperation.Payload(
                companyId: previous.companyId, siteVisitId: previous.siteVisitId, entityId: previous.entityId,
                completion: previous.completion, stageCommand: previous.stageCommand, writeCommand: command))
        }
    }
    static func enqueueTemplates(_ types: [SiteVisitType], context: ModelContext) throws {
        let command = try SiteVisitWriteModels.command(types)
        let unresolved = try context.fetch(FetchDescriptor<SyncOperation>()).filter {
            $0.entityType == SyncEntityType.siteVisitType.rawValue && $0.status != "completed" &&
                self.command($0)?.companyId == command.companyId
        }.sorted { $0.createdAt < $1.createdAt }
        let operation = SyncOperation(entityType: SyncEntityType.siteVisitType.rawValue,
            entityId: command.rows[0].id, operationType: "siteVisitWrite",
            payload: try JSONEncoder().encode(command), changedFields: SiteVisitTypeServerMerge.mutableFields.sorted(),
            dependsOnId: unresolved.last?.id.uuidString.lowercased())
        operation.siteVisitWriteActorId = SiteVisitAuthorHeal.sessionUserId()?.lowercased()
        context.insert(operation)
    }
    @MainActor
    static func deliver(id: UUID, command: SiteVisitWriteCommand, expectedActorId: String) async throws -> SiteVisitWriteReceipt {
        struct Parameters: Encodable { let p_command_id: UUID; let p_command: SiteVisitWriteCommand; let p_expected_actor: String }
        return try await SupabaseService.shared.client.rpc(command.applyRPC,
            params: Parameters(p_command_id: id, p_command: command, p_expected_actor: expectedActorId)).execute().value
    }
    static func execute(operation: SyncOperation, context: ModelContext, companyId: String, actorId: String?,
                        isCurrent: () -> Bool, deliverWrite: Deliver = { try await deliver(id: $0, command: $1, expectedActorId: $2) },
                        deliverResolution: DeliverResolution = { try await Self.deliverResolution(originalId: $0, command: $1, resolution: $2, expectedActorId: $3, useChoiceProtocol: $4) },
                        isolation: isolated (any Actor)? = #isolation) async throws {
        guard var command = command(operation), command.isSupported,
              command.companyId == companyId.lowercased(), !command.rows.isEmpty,
              command.rows.contains(where: { $0.id == operation.entityId.lowercased() }),
              let actorId = actorId?.lowercased(), !actorId.isEmpty,
              operation.siteVisitWriteActorId == actorId else { throw SiteVisitWriteError.legacyPayload }
        let resolutionData = operation.siteVisitWriteResolutionData
        if operation.siteVisitWriteAttemptedAt == nil {
            // A command that has not left the phone may still move onto the
            // newest revision this queue has already seen for its rows. Once
            // frozen it never changes: the server keys idempotency on its bytes.
            if resolutionData == nil,
               let rebased = try rebasedOntoOwnSavedRevisions(command, operation: operation, context: context) {
                try setCommand(rebased, on: operation)
                command = rebased
            }
            operation.siteVisitWriteAttemptedAt = Date()
            try context.save() // Durable before transmission; never reset by Retry.
        }
        let resolution = try resolutionData.map { try JSONDecoder().decode(SiteVisitWriteResolution.self, from: $0) }
        let receipt: SiteVisitWriteReceipt
        if let resolution {
            let currentRequiresChoiceProtocol = try SiteVisitWriteModels.needsChoiceReview(command, context: context)
            let useChoiceProtocol = resolution.current.contains(where: \.containsChoiceMetadata)
                || currentRequiresChoiceProtocol
            receipt = try await deliverResolution(operation.id, command, resolution, actorId, useChoiceProtocol)
        } else {
            receipt = try await deliverWrite(operation.id, command, actorId)
        }
        guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
        do {
            try applyReceipt(receipt, to: operation, command: command, resolutionData: resolutionData,
                context: context, companyId: companyId, actorId: actorId)
        } catch SiteVisitWriteError.conflict where resolutionData == nil {
            // The phone conflicting with its own earlier save is not a review
            // question — the local edit already builds on that save. Settle it
            // as USE PENDING in this pass; a foreign row still parks for review.
            guard let selfResolution = try selfConflictResolution(for: receipt, command: command,
                                                                  operation: operation, context: context) else {
                throw SiteVisitWriteError.conflict
            }
            let selfResolutionData = try JSONEncoder().encode(selfResolution)
            operation.siteVisitWriteResolutionData = selfResolutionData
            try context.save()
            let currentRequiresChoiceProtocol = try SiteVisitWriteModels.needsChoiceReview(command, context: context)
            let useChoiceProtocol = selfResolution.current.contains(where: \.containsChoiceMetadata)
                || currentRequiresChoiceProtocol
            let settled = try await deliverResolution(operation.id, command, selfResolution, actorId, useChoiceProtocol)
            guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
            try applyReceipt(settled, to: operation, command: command, resolutionData: selfResolutionData,
                context: context, companyId: companyId, actorId: actorId)
        }
    }

    /// The highest revision this queue has already seen for each row of an
    /// unattempted command — its own `saved` receipts, rows a review settled,
    /// and the persisted write state — is the only honest base for it. Bug
    /// 0e110106: a successor queued from a stale in-memory write state shipped
    /// the revision from before the phone's own save and could never land.
    /// Conflict receipts are never a source: their rows may be another writer's.
    private static func rebasedOntoOwnSavedRevisions(_ command: SiteVisitWriteCommand, operation: SyncOperation,
                                                    context: ModelContext) throws -> SiteVisitWriteCommand? {
        let seen = try ownSeenRows(for: command, operation: operation,
            outcomes: ["saved", "resolved", "superseded"], context: context)
        var rebased = command
        var changed = false
        for index in rebased.rows.indices {
            let row = rebased.rows[index]
            var best: (revision: Int64, row: SiteVisitWriteJSON)?
            for candidate in seen where candidate["id"]?.string == row.id {
                guard let revision = candidate["write_revision"]?.revision,
                      revision > (best?.revision ?? -1) else { continue }
                best = (revision, candidate)
            }
            if let state = try persistedWriteState(entity: command.entity, id: row.id, companyId: command.companyId, context: context),
               state.revision > (best?.revision ?? -1) {
                let serverRow = [state.baseRow, state.remoteRow].compactMap { $0 }
                    .first { $0["write_revision"]?.revision == state.revision }
                best = (state.revision, serverRow ?? row.before)
            }
            guard let best, best.revision > row.baseRevision else { continue }
            rebased.rows[index].baseRevision = best.revision
            rebased.rows[index].before = best.row
            changed = true
        }
        return changed ? rebased : nil
    }

    /// A `stale_edit` whose current rows are, byte for byte, rows this queue
    /// itself delivered is the phone conflicting with its own earlier save.
    /// The local edit already builds on that save, so USE PENDING is the only
    /// answer the operator could give. Anything else stays a real conflict.
    private static func selfConflictResolution(for receipt: SiteVisitWriteReceipt, command: SiteVisitWriteCommand,
                                               operation: SyncOperation, context: ModelContext) throws -> SiteVisitWriteResolution? {
        guard receipt.outcome == "conflict", receipt.reason == "stale_edit",
              receipt.rows.count == command.rows.count else { return nil }
        let delivered = try ownSeenRows(for: command, operation: operation, outcomes: ["saved"], context: context)
        for row in command.rows {
            guard let current = receipt.rows.first(where: { $0["id"]?.string == row.id }),
                  delivered.contains(current) else { return nil }
        }
        return SiteVisitWriteResolution(id: UUID(), choice: "pending", current: receipt.rows)
    }

    /// Rows the server has echoed back to THIS queue for the command's rows:
    /// receipts of other operations with one of `outcomes`, same company.
    private static func ownSeenRows(for command: SiteVisitWriteCommand, operation: SyncOperation, outcomes: Set<String>,
                                    context: ModelContext) throws -> [SiteVisitWriteJSON] {
        let rowIds = Set(command.rows.map(\.id))
        return try context.fetch(FetchDescriptor<SyncOperation>()).flatMap { candidate -> [SiteVisitWriteJSON] in
            guard candidate.id != operation.id, candidate.entityType == operation.entityType,
                  command.entity == "template" || rowIds.contains(candidate.entityId.lowercased()),
                  let data = candidate.siteVisitWriteReceiptData,
                  let receipt = try? JSONDecoder().decode(SiteVisitWriteReceipt.self, from: data),
                  receipt.entity == command.entity, outcomes.contains(receipt.outcome) else { return [] }
            return receipt.rows.filter { $0["company_id"]?.string == command.companyId }
        }
    }

    /// The write state as the store holds it — never the registered object a
    /// view model may still be showing from before a receipt landed.
    private static func persistedWriteState(entity: String, id: String, companyId: String,
                                            context: ModelContext) throws -> SiteVisitWriteState? {
        let fresh = ModelContext(context.container)
        if entity == "template" {
            guard let type = try SiteVisitTypeServerMerge.fetch(id: id, context: fresh),
                  type.companyId.lowercased() == companyId else { return nil }
            return type.writeState
        }
        guard let answer = try fresh.fetch(FetchDescriptor<SiteVisitChecklistAnswer>(predicate: #Predicate { $0.id == id })).first,
              answer.companyId.lowercased() == companyId else { return nil }
        return answer.writeState
    }

    /// A network suspension can leave registered SwiftData objects older than
    /// edits committed by another context. Apply only against a fresh read.
    static func applyReceipt(_ receipt: SiteVisitWriteReceipt, to originalOperation: SyncOperation,
                             command: SiteVisitWriteCommand, resolutionData: Data?,
                             context originalContext: ModelContext, companyId: String, actorId: String) throws {
        let resolution = try resolutionData.map { try JSONDecoder().decode(SiteVisitWriteResolution.self, from: $0) }
        let operationId = originalOperation.id
        let verificationContext = ModelContext(originalContext.container)
        guard let latest = try verificationContext.fetch(FetchDescriptor<SyncOperation>(predicate: #Predicate { $0.id == operationId })).first,
              latest.siteVisitWriteResolutionData == resolutionData,
              latest.siteVisitWriteActorId == actorId,
              latest.payload == originalOperation.payload,
              self.command(latest) == command else { throw CancellationError() }
        let discarded = try verificationContext.fetch(FetchDescriptor<SyncOperation>()).contains { candidate in
            guard candidate.operationType == SiteVisitSyncOperation.discardOperationType,
                  candidate.siteVisitWriteReceiptData != nil,
                  let intent = (try? JSONDecoder().decode(SiteVisitSyncOperation.Payload.self, from: candidate.payload))?.discard else { return false }
            return intent.supersededOperationIds.contains(operationId)
        }
        guard !discarded else { throw CancellationError() }
        let context = verificationContext
        let operation = latest
        guard receipt.commandId == (resolution?.id ?? operation.id), receipt.entity == command.entity,
              ["saved", "conflict", "resolved", "superseded"].contains(receipt.outcome),
              receipt.rows.allSatisfy({ $0["company_id"]?.string == companyId.lowercased() }) else {
            throw SiteVisitWriteError.invalidReceipt
        }
        if receipt.outcome == "saved" && resolution == nil {
            guard Set(receipt.rows.compactMap { $0["id"]?.string }) == Set(command.rows.map(\.id)),
                  receipt.rows.count == command.rows.count,
                  receipt.rows.allSatisfy({ $0["write_revision"]?.revision != nil }) else {
                throw SiteVisitWriteError.invalidReceipt
            }
            // Readback must include every exact requested value. Server-owned
            // revisions/timestamps/author and derived parent links are separate.
            for requested in command.rows {
                guard let actual = receipt.rows.first(where: { $0["id"]?.string == requested.id }),
                      actual.matchesRequested(requested.values),
                      requested.clearAnswer != true || actual["answer_state"]?.string == "cleared" else { throw SiteVisitWriteError.invalidReceipt }
            }
        }
        if let resolution, receipt.outcome == "resolved" {
            guard resolution.choice == "current", receipt.rows == resolution.current else { throw SiteVisitWriteError.invalidReceipt }
        }
        if let resolution, receipt.outcome == "saved" {
            guard resolution.choice == "pending" else { throw SiteVisitWriteError.invalidReceipt }
            for row in command.rows {
                let actual = receipt.rows.first { $0["id"]?.string == row.id } ?? receipt.rows.first {
                    (command.entity == "answer" && $0["field_id"] == row.values["field_id"] && $0["site_visit_id"] == row.values["site_visit_id"]) || (command.entity == "template" && $0["slug"] == row.values["slug"])
                }
                var expected = command.entity == "answer" ? SiteVisitWriteJSON.object([
                    "answer_value": row.values["answer_value"] ?? .null, "deleted_at": row.values["deleted_at"] ?? .null
                ]) : row.values
                if command.entity == "answer" {
                    let reviewedByID = resolution.current.first { $0["id"]?.string == row.id }
                    let collisions = resolution.current.filter {
                        $0["company_id"]?.string == command.companyId &&
                        $0["site_visit_id"] == row.values["site_visit_id"] &&
                        $0["field_id"] == row.values["field_id"] && $0["deleted_at"]?.string == nil
                    }
                    guard reviewedByID != nil || collisions.count <= 1 else { throw SiteVisitWriteError.invalidReceipt }
                    let reviewed = reviewedByID ?? collisions.first
                    let isCollision = reviewedByID == nil && reviewed != nil
                    let adoptsReviewedSnapshot = isCollision ||
                        (command.protocol == SiteVisitWriteCommand.revision && row.values["choice_snapshot"] == nil && reviewed != nil)
                    let snapshot = adoptsReviewedSnapshot ? reviewed?["choice_snapshot"] : row.values["choice_snapshot"]
                    // Only an explicitly reviewed canonical answer can replace
                    // the proposed identity/snapshot. Ordinary v2 writes retain
                    // their original exact snapshot requirement.
                    guard let actual, actual["id"]?.string == (reviewed?["id"]?.string ?? row.id),
                          actual["company_id"]?.string == command.companyId,
                          actual["site_visit_id"] == row.values["site_visit_id"],
                          actual["field_id"] == row.values["field_id"],
                          (actual["choice_snapshot"] ?? .null) == (snapshot ?? .null) else {
                        throw SiteVisitWriteError.invalidReceipt
                    }
                    if let reviewed {
                        guard reviewed["company_id"]?.string == command.companyId,
                              reviewed["site_visit_id"] == row.values["site_visit_id"],
                              reviewed["field_id"] == row.values["field_id"],
                              (actual["choice_snapshot"] ?? .null) == (reviewed["choice_snapshot"] ?? .null) else {
                            throw SiteVisitWriteError.invalidReceipt
                        }
                    }
                }
                if command.entity == "template", case .object(var values) = expected, let actual {
                    values["id"] = actual["id"]; expected = .object(values)
                }
                guard let actual, actual["write_revision"]?.revision != nil, actual.matchesRequested(expected),
                      row.clearAnswer != true || actual["answer_state"]?.string == "cleared" else { throw SiteVisitWriteError.invalidReceipt }
            }
        }
        var rebasedCommands: [(PersistentIdentifier, Data)] = []
        try context.transaction {
            operation.siteVisitWriteReceiptData = try JSONEncoder().encode(receipt)
            if receipt.outcome == "conflict", let resolution {
                var history = operation.siteVisitWriteResolutionHistoryData.flatMap { try? JSONDecoder().decode([SiteVisitWriteResolution].self, from: $0) } ?? []
                history.append(resolution)
                operation.siteVisitWriteResolutionHistoryData = try JSONEncoder().encode(history)
                operation.siteVisitWriteResolutionData = nil
            }
            let all = try context.fetch(FetchDescriptor<SyncOperation>())
            for descendant in all where descendant.id != operation.id && descendant.status != "completed" &&
                resolution == nil && descendant.siteVisitWriteAttemptedAt == nil && hasAncestor(operation.id, operation: descendant, all: all) {
                if var next = self.command(descendant) {
                    next.acknowledgePredecessor(receipt)
                    try setCommand(next, on: descendant)
                    rebasedCommands.append((descendant.persistentModelID, descendant.payload))
                }
            }
            for row in command.rows {
                let id = row.id
                let saved = receipt.rows.first { $0["id"]?.string == id } ?? (resolution != nil ? receipt.rows.first {
                    (command.entity == "answer" && $0["field_id"] == row.values["field_id"] && $0["site_visit_id"] == row.values["site_visit_id"]) || (command.entity == "template" && $0["slug"] == row.values["slug"])
                } : nil)
                let hasLater = all.contains { candidate in
                    candidate.id != operation.id && candidate.status != "completed" &&
                        hasAncestor(operation.id, operation: candidate, all: all) &&
                        self.command(candidate)?.rows.contains(where: { $0.id == id }) == true
                }
                if command.entity == "answer", let model = try context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>(predicate: #Predicate { $0.id == id })).first {
                    let exactLocal = SiteVisitWriteModels.values(model).matchesRequested(row.values)
                    if receipt.outcome == "conflict" || hasLater || !exactLocal {
                        var state = model.writeState
                        state.remoteRow = saved
                        // A saved row with this identity is the phone's own
                        // newest revision whether or not a successor is queued
                        // yet (bug 0e110106): every later edit builds on it.
                        if receipt.outcome == "saved", let saved, saved["id"]?.string == id,
                           let revision = saved["write_revision"]?.revision {
                            state.revision = revision
                            state.baseRevision = revision; state.baseRow = saved
                        }
                        model.writeState = state; model.needsSync = true
                    } else if let saved {
                        if resolution != nil || receipt.outcome == "superseded" {
                            let dto = try JSONDecoder().decode(SiteVisitChecklistAnswerDTO.self, from: JSONEncoder().encode(saved))
                            try acceptResolved(dto, row: saved, proposal: model, context: context)
                        }
                        var state = model.writeState; state.accept(saved); model.writeState = state
                        model.needsSync = false; model.lastSyncedAt = Date()
                    } else if receipt.outcome == "resolved" || receipt.outcome == "superseded" {
                        model.deletedAt = Date(); model.needsSync = false; model.lastSyncedAt = Date()
                        model.writeState = .init()
                    }
                } else if command.entity == "template", let model = try SiteVisitTypeServerMerge.fetch(id: id, context: context) {
                    let exactLocal = SiteVisitWriteModels.values(model).matchesRequested(row.values)
                    if receipt.outcome == "conflict" || hasLater || !exactLocal {
                        var state = model.writeState; state.remoteRow = saved
                        if receipt.outcome == "saved", let saved, saved["id"]?.string == id,
                           let revision = saved["write_revision"]?.revision {
                            state.revision = revision
                            state.baseRevision = revision; state.baseRow = saved
                        }
                        model.writeState = state; model.needsSync = true
                    } else if let saved {
                        if resolution != nil || receipt.outcome == "superseded" {
                            let dto = try JSONDecoder().decode(SiteVisitTypeDTO.self, from: JSONEncoder().encode(saved))
                            try acceptResolved(dto, row: saved, proposal: model, context: context)
                        }
                        var state = model.writeState; state.accept(saved); model.writeState = state
                        model.needsSync = false; model.lastSyncedAt = Date()
                    } else if receipt.outcome == "resolved" || receipt.outcome == "superseded" {
                        model.deletedAt = Date(); model.needsSync = false; model.lastSyncedAt = Date()
                        model.writeState = .init()
                    }
                }
            }
            if resolution != nil && receipt.outcome == "saved" && command.entity == "template" {
                for saved in receipt.rows where !command.rows.contains(where: { $0.id == saved["id"]?.string }) {
                    let dto = try JSONDecoder().decode(SiteVisitTypeDTO.self, from: JSONEncoder().encode(saved))
                    try SiteVisitTypeServerMerge.merge(dto: dto, accepting: SiteVisitTypeServerMerge.mutableFields,
                        hasPendingLocalOperation: false, context: context)
                }
            }
        }
        // The owning engine still updates status on its registered operation.
        // Carry the receipt bookkeeping back so that save cannot reinstate an
        // older resolution while leaving freshly read entity models untouched.
        for (id, payload) in rebasedCommands {
            let registered: SyncOperation? = originalContext.registeredModel(for: id)
            if let registered, registered.siteVisitWriteAttemptedAt == nil { registered.payload = payload }
        }
        originalOperation.siteVisitWriteReceiptData = operation.siteVisitWriteReceiptData
        originalOperation.siteVisitWriteResolutionData = operation.siteVisitWriteResolutionData
        originalOperation.siteVisitWriteResolutionHistoryData = operation.siteVisitWriteResolutionHistoryData
        if receipt.outcome == "conflict" { throw SiteVisitWriteError.conflict }
    }
    private static func acceptResolved(_ dto: SiteVisitChecklistAnswerDTO, row: SiteVisitWriteJSON,
                                       proposal: SiteVisitChecklistAnswer, context: ModelContext) throws {
        let id = dto.id
        let canonical = try context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>(predicate: #Predicate { $0.id == id })).first
        let target = canonical ?? proposal
        if target !== proposal && (target.needsSync || target.writeState.baseRevision != nil) {
            var state = target.writeState; state.remoteRow = row; target.writeState = state
        } else {
            target.id = dto.id; try target.acceptServerValue(dto.hydratedAnswerValue); target.deletedAt = dto.deletedAt
            target.siteVisitTypeId = dto.siteVisitTypeId; target.fieldId = dto.fieldId; target.label = dto.label
            target.kind = dto.kind; target.required = dto.required; target.helpText = dto.helpText; target.sortOrder = dto.sortOrder
            var state = target.writeState; state.accept(row); target.writeState = state
            target.needsSync = false; target.lastSyncedAt = Date()
        }
        if target !== proposal { proposal.deletedAt = Date() }
    }
    private static func acceptResolved(_ dto: SiteVisitTypeDTO, row: SiteVisitWriteJSON,
                                       proposal: SiteVisitType, context: ModelContext) throws {
        let id = dto.id
        let canonical = try SiteVisitTypeServerMerge.fetch(id: id, context: context)
        let target = canonical ?? proposal
        if target !== proposal && (target.needsSync || target.writeState.baseRevision != nil) {
            var state = target.writeState; state.remoteRow = row; target.writeState = state
        } else {
            target.id = dto.id; target.slug = dto.slug; target.name = dto.name; target.descriptionText = dto.descriptionText
            target.isDefault = dto.isDefault; target.fields = dto.fields; target.sortOrder = dto.sortOrder
            target.deletedAt = dto.deletedAt.flatMap(SupabaseDate.parse)
            var state = target.writeState; state.accept(row); target.writeState = state
            target.needsSync = false; target.lastSyncedAt = Date()
        }
        if target !== proposal { proposal.deletedAt = Date(); proposal.isDefault = false }
    }
    @MainActor
    static func review(_ command: SiteVisitWriteCommand, expectedActorId: String, useChoiceProtocol: Bool = false) async throws -> [SiteVisitWriteJSON] {
        struct Parameters: Encodable { let p_command: SiteVisitWriteCommand; let p_expected_actor: String }
        struct Response: Decodable { let rows: [SiteVisitWriteJSON] }
        let response: Response = try await SupabaseService.shared.client.rpc(useChoiceProtocol ? "review_site_visit_write_v2" : command.reviewRPC,
            params: Parameters(p_command: command, p_expected_actor: expectedActorId)).execute().value
        guard response.rows.allSatisfy({ $0["company_id"]?.string == command.companyId }) else { throw SiteVisitWriteError.invalidReceipt }
        return response.rows
    }
    @MainActor
    static func deliverResolution(originalId: UUID, command: SiteVisitWriteCommand, resolution: SiteVisitWriteResolution, expectedActorId: String, useChoiceProtocol: Bool = false) async throws -> SiteVisitWriteReceipt {
        struct Parameters: Encodable {
            let p_resolution_id: UUID; let p_original_id: UUID; let p_command: SiteVisitWriteCommand
            let p_choice: String; let p_current: [SiteVisitWriteJSON]; let p_expected_actor: String
        }
        return try await SupabaseService.shared.client.rpc(useChoiceProtocol ? "resolve_site_visit_write_v2" : command.resolveRPC, params: Parameters(
            p_resolution_id: resolution.id, p_original_id: originalId, p_command: command,
            p_choice: resolution.choice, p_current: resolution.current, p_expected_actor: expectedActorId)).execute().value
    }
    private static func hasAncestor(_ id: UUID, operation: SyncOperation, all: [SyncOperation]) -> Bool {
        var cursor = operation.dependsOnId?.lowercased()
        var seen = Set<String>()
        while let current = cursor, seen.insert(current).inserted {
            if current == id.uuidString.lowercased() { return true }
            cursor = all.first { $0.id.uuidString.lowercased() == current }?.dependsOnId?.lowercased()
        }
        return false
    }
}
