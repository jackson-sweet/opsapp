//
//  HistoricalSiteVisitSettlementCoordinator.swift
//  OPS
//
//  Explicit two-phase executor for the audited historical site-visit repair.
//  Nothing constructs or calls this from the normal sync engine. A caller must
//  first prepare one exact plan, obtain a matching approval, and then execute
//  that single plan. The receipt ledger makes interrupted execution resumable.
//

import Foundation
import Supabase
import SwiftData

enum HistoricalSiteVisitSettlementReceiptPhase: String, Codable, Equatable {
    case prepared
    case applied
}

struct HistoricalSiteVisitSettlementReceipt: Codable, Equatable {
    let plan: HistoricalSiteVisitSettlementPlan
    let approval: HistoricalSiteVisitSettlementApproval
    let phase: HistoricalSiteVisitSettlementReceiptPhase
    let preparedAt: Date
    let appliedAt: Date?
    let serverMutationPerformed: Bool
}

@MainActor
protocol HistoricalSiteVisitSettlementReceiptStoring: AnyObject {
    func receipt(approvalDigest: String) throws -> HistoricalSiteVisitSettlementReceipt?
    func prepare(
        plan: HistoricalSiteVisitSettlementPlan,
        approval: HistoricalSiteVisitSettlementApproval,
        at date: Date
    ) throws -> HistoricalSiteVisitSettlementReceipt
    func markApplied(
        approvalDigest: String,
        serverMutationPerformed: Bool,
        at date: Date
    ) throws -> HistoricalSiteVisitSettlementReceipt
}

@MainActor
final class HistoricalSiteVisitSettlementReceiptStore:
    HistoricalSiteVisitSettlementReceiptStoring
{
    private let directoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    convenience init(fileManager: FileManager = .default) throws {
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.init(
            directoryURL: root.appendingPathComponent(
                "HistoricalSiteVisitSettlements",
                isDirectory: true
            ),
            fileManager: fileManager
        )
    }

    func receipt(approvalDigest: String) throws -> HistoricalSiteVisitSettlementReceipt? {
        let url = try receiptURL(approvalDigest: approvalDigest)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(
            HistoricalSiteVisitSettlementReceipt.self,
            from: Data(contentsOf: url)
        )
    }

    func prepare(
        plan: HistoricalSiteVisitSettlementPlan,
        approval: HistoricalSiteVisitSettlementApproval,
        at date: Date
    ) throws -> HistoricalSiteVisitSettlementReceipt {
        if let existing = try receipt(approvalDigest: plan.approvalDigest) {
            guard existing.plan == plan, existing.approval == approval else {
                throw HistoricalSiteVisitSettlementError.auditConflict
            }
            return existing
        }
        let receipt = HistoricalSiteVisitSettlementReceipt(
            plan: plan,
            approval: approval,
            phase: .prepared,
            preparedAt: date,
            appliedAt: nil,
            serverMutationPerformed: false
        )
        try write(receipt)
        return receipt
    }

    func markApplied(
        approvalDigest: String,
        serverMutationPerformed: Bool,
        at date: Date
    ) throws -> HistoricalSiteVisitSettlementReceipt {
        guard let existing = try receipt(approvalDigest: approvalDigest) else {
            throw HistoricalSiteVisitSettlementError.auditConflict
        }
        if existing.phase == .applied {
            guard existing.serverMutationPerformed == serverMutationPerformed else {
                throw HistoricalSiteVisitSettlementError.auditConflict
            }
            return existing
        }
        let applied = HistoricalSiteVisitSettlementReceipt(
            plan: existing.plan,
            approval: existing.approval,
            phase: .applied,
            preparedAt: existing.preparedAt,
            appliedAt: date,
            serverMutationPerformed: serverMutationPerformed
        )
        try write(applied)
        return applied
    }

    private func write(_ receipt: HistoricalSiteVisitSettlementReceipt) throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        var directoryValues = URLResourceValues()
        directoryValues.isExcludedFromBackup = true
        var mutableDirectoryURL = directoryURL
        try mutableDirectoryURL.setResourceValues(directoryValues)
        try encoder.encode(receipt).write(
            to: try receiptURL(approvalDigest: receipt.plan.approvalDigest),
            options: [.atomic, .completeFileProtection]
        )
    }

    private func receiptURL(approvalDigest: String) throws -> URL {
        let canonical = approvalDigest.lowercased()
        guard canonical.count == 64,
              canonical.allSatisfy({ $0.isHexDigit }) else {
            throw HistoricalSiteVisitSettlementError.auditConflict
        }
        return directoryURL.appendingPathComponent("\(canonical).json", isDirectory: false)
    }
}

@MainActor
protocol HistoricalSiteVisitSettlementRemote: AnyObject {
    func fetchBundle(siteVisitId: String) async throws -> SiteVisitBundleDTO
    func compareAndSetUnlinkedActiveVisit(
        visitId: String,
        companyId: String,
        targetOpportunityId: String,
        expectedStatus: SiteVisitStatus,
        expectedUpdatedAt: Date
    ) async throws -> SiteVisitBundleDTO
}

@MainActor
final class HistoricalSiteVisitSettlementSupabaseRemote:
    HistoricalSiteVisitSettlementRemote
{
    private struct LinkPayload: Encodable {
        let opportunityId: String

        enum CodingKeys: String, CodingKey {
            case opportunityId = "opportunity_id"
        }
    }

    private let companyId: String
    private let client: SupabaseClient
    private let repository: SiteVisitRepository

    init(companyId: String, client: SupabaseClient) {
        self.companyId = companyId.lowercased()
        self.client = client
        repository = SiteVisitRepository(
            companyId: companyId,
            transport: HistoricalReadTransport(client: client)
        )
    }

    convenience init(companyId: String) {
        self.init(companyId: companyId, client: SupabaseService.shared.client)
    }

    func fetchBundle(siteVisitId: String) async throws -> SiteVisitBundleDTO {
        try await repository.fetchBundle(siteVisitId: siteVisitId)
    }

    func compareAndSetUnlinkedActiveVisit(
        visitId: String,
        companyId: String,
        targetOpportunityId: String,
        expectedStatus: SiteVisitStatus,
        expectedUpdatedAt: Date
    ) async throws -> SiteVisitBundleDTO {
        let canonicalCompany = companyId.lowercased()
        guard canonicalCompany == self.companyId else {
            throw SiteVisitRepositoryError.companyMismatch(
                expected: self.companyId,
                received: canonicalCompany
            )
        }
        guard expectedStatus == .scheduled || expectedStatus == .inProgress else {
            throw HistoricalSiteVisitSettlementError.statusMismatch
        }
        do {
            let data = try await client
                .from("site_visits")
                .update(LinkPayload(opportunityId: targetOpportunityId.lowercased()))
                .eq("id", value: visitId.lowercased())
                .eq("company_id", value: canonicalCompany)
                .eq("status", value: expectedStatus.rawValue)
                .eq("updated_at", value: SupabaseDate.format(expectedUpdatedAt))
                .is("deleted_at", value: nil)
                .is("opportunity_id", value: nil)
                .select()
                .single()
                .execute()
                .data
            _ = try JSONDecoder().decode(SiteVisitDTO.self, from: data)
            return try await fetchBundle(siteVisitId: visitId)
        } catch {
            throw SiteVisitRepositoryError.wrapping(error)
        }
    }
}

/// Read-only adapter reused solely because `SiteVisitRepository.fetchBundle`
/// already owns strict DTO decoding. It refuses every write request.
private final class HistoricalReadTransport: SiteVisitRemoteTransport {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func send(_ request: SiteVisitRemoteRequest) async throws -> Data {
        guard case let .fetch(table, companyId, since, siteVisitId) = request else {
            throw HistoricalSiteVisitSettlementError.serverMutationForbidden
        }
        var query = client
            .from(table.rawValue)
            .select()
            .eq("company_id", value: companyId)
        if let since {
            query = query.gte("updated_at", value: SupabaseDate.format(since))
        }
        if let siteVisitId {
            query = query.eq(
                table == .visits ? "id" : "site_visit_id",
                value: siteVisitId
            )
        }
        return try await query
            .order("updated_at", ascending: true)
            .execute()
            .data
    }
}

@MainActor
final class HistoricalSiteVisitSettlementCoordinator {
    private let context: ModelContext
    private let remote: HistoricalSiteVisitSettlementRemote
    private let receipts: HistoricalSiteVisitSettlementReceiptStoring
    private let manifest: HistoricalSiteVisitSettlementManifest

    init(
        context: ModelContext,
        remote: HistoricalSiteVisitSettlementRemote,
        receipts: HistoricalSiteVisitSettlementReceiptStoring,
        manifest: HistoricalSiteVisitSettlementManifest = .preIncidentUnlinkedVisits
    ) {
        self.context = context
        self.remote = remote
        self.receipts = receipts
        self.manifest = manifest
    }

    func prepare(
        visitId: String,
        actorUserId: String,
        accessPolicy: LeadAccessPolicy
    ) async throws -> HistoricalSiteVisitSettlementPlan {
        guard let entry = manifest.entry(for: visitId) else {
            throw HistoricalSiteVisitSettlementError.visitOutsideManifest
        }
        let phone = try HistoricalSiteVisitSettlementEvidenceFactory.phone(
            entry: entry,
            actorUserId: actorUserId,
            accessPolicy: accessPolicy,
            context: context
        )
        let server = try HistoricalSiteVisitSettlementEvidenceFactory.server(
            try await remote.fetchBundle(siteVisitId: entry.visitId)
        )
        let capability = try HistoricalSiteVisitSettlementEvidenceFactory.capability(
            entry: entry,
            actorUserId: actorUserId,
            accessPolicy: accessPolicy,
            context: context
        )
        return try HistoricalSiteVisitSettlementPolicy.plan(
            manifest: manifest,
            phone: phone,
            server: server,
            capability: capability
        )
    }

    @discardableResult
    func execute(
        plan: HistoricalSiteVisitSettlementPlan,
        approval: HistoricalSiteVisitSettlementApproval,
        accessPolicy: LeadAccessPolicy,
        now: Date = Date()
    ) async throws -> HistoricalSiteVisitSettlementReceipt {
        try HistoricalSiteVisitSettlementPolicy.validate(approval, for: plan)
        guard let entry = manifest.entry(for: plan.visitId) else {
            throw HistoricalSiteVisitSettlementError.visitOutsideManifest
        }
        let capability = try HistoricalSiteVisitSettlementEvidenceFactory.capability(
            entry: entry,
            actorUserId: approval.actorUserId,
            accessPolicy: accessPolicy,
            context: context
        )
        guard capability.canEditTargetOpportunity else {
            throw HistoricalSiteVisitSettlementError.capabilityDenied
        }

        if let existing = try receipts.receipt(approvalDigest: plan.approvalDigest),
           existing.phase == .applied {
            guard existing.plan == plan, existing.approval == approval else {
                throw HistoricalSiteVisitSettlementError.auditConflict
            }
            return existing
        }

        var serverBundle = try await remote.fetchBundle(siteVisitId: plan.visitId)
        var serverEvidence = try HistoricalSiteVisitSettlementEvidenceFactory.server(serverBundle)
        let existingPrepared = try receipts.receipt(approvalDigest: plan.approvalDigest)

        if existingPrepared == nil {
            let phone = try HistoricalSiteVisitSettlementEvidenceFactory.phone(
                entry: entry,
                actorUserId: approval.actorUserId,
                accessPolicy: accessPolicy,
                context: context
            )
            let freshPlan = try HistoricalSiteVisitSettlementPolicy.plan(
                manifest: manifest,
                phone: phone,
                server: serverEvidence,
                capability: capability
            )
            guard freshPlan == plan else {
                throw HistoricalSiteVisitSettlementError.approvalMismatch
            }
            _ = try receipts.prepare(plan: plan, approval: approval, at: now)
        } else {
            guard existingPrepared?.plan == plan, existingPrepared?.approval == approval else {
                throw HistoricalSiteVisitSettlementError.auditConflict
            }
        }

        var serverMutationPerformed = false
        switch plan.outcome {
        case .recoverActiveLink:
            if serverEvidence.opportunityId == nil {
                let phone = try HistoricalSiteVisitSettlementEvidenceFactory.phone(
                    entry: entry,
                    actorUserId: approval.actorUserId,
                    accessPolicy: accessPolicy,
                    context: context
                )
                let replayPlan = try HistoricalSiteVisitSettlementPolicy.plan(
                    manifest: manifest,
                    phone: phone,
                    server: serverEvidence,
                    capability: capability
                )
                guard replayPlan == plan else {
                    throw HistoricalSiteVisitSettlementError.approvalMismatch
                }
                serverBundle = try await remote.compareAndSetUnlinkedActiveVisit(
                    visitId: plan.visitId,
                    companyId: plan.companyId,
                    targetOpportunityId: plan.targetOpportunityId,
                    expectedStatus: plan.expectedServerStatus,
                    expectedUpdatedAt: plan.expectedServerUpdatedAt
                )
                serverEvidence = try HistoricalSiteVisitSettlementEvidenceFactory.server(serverBundle)
                serverMutationPerformed = true
            }
            try validateLinkedServerEvidence(serverEvidence, plan: plan)
            try HistoricalSiteVisitSettlementLocalMutation.rearmActivePacket(
                plan: plan,
                in: context
            )

        case .settleCompletedHistory:
            if try HistoricalSiteVisitSettlementLocalMutation.isApplied(
                plan: plan,
                in: context
            ) {
                try validateCompletedServerEvidence(serverEvidence, plan: plan)
            } else {
                let phone = try HistoricalSiteVisitSettlementEvidenceFactory.phone(
                    entry: entry,
                    actorUserId: approval.actorUserId,
                    accessPolicy: accessPolicy,
                    context: context
                )
                let replayPlan = try HistoricalSiteVisitSettlementPolicy.plan(
                    manifest: manifest,
                    phone: phone,
                    server: serverEvidence,
                    capability: capability
                )
                guard replayPlan == plan else {
                    throw HistoricalSiteVisitSettlementError.approvalMismatch
                }
                try HistoricalSiteVisitSettlementLocalMutation.settleCompletedPacket(
                    plan: plan,
                    in: context,
                    now: now
                )
            }
        }

        return try receipts.markApplied(
            approvalDigest: plan.approvalDigest,
            serverMutationPerformed: serverMutationPerformed,
            at: now
        )
    }

    private func validateLinkedServerEvidence(
        _ evidence: HistoricalSiteVisitServerEvidence,
        plan: HistoricalSiteVisitSettlementPlan
    ) throws {
        guard evidence.visitId == plan.visitId,
              evidence.companyId == plan.companyId,
              evidence.status == plan.expectedServerStatus,
              evidence.deletedAt == nil,
              evidence.opportunityId == plan.targetOpportunityId,
              evidence.childRelationships.allSatisfy({
                  $0.siteVisitId == plan.visitId
                      && $0.companyId == plan.companyId
                      && $0.opportunityId == plan.targetOpportunityId
              }) else {
            throw HistoricalSiteVisitSettlementError.serverRelationshipConflict
        }
    }

    private func validateCompletedServerEvidence(
        _ evidence: HistoricalSiteVisitServerEvidence,
        plan: HistoricalSiteVisitSettlementPlan
    ) throws {
        guard evidence.visitId == plan.visitId,
              evidence.companyId == plan.companyId,
              evidence.status == .completed,
              evidence.deletedAt == nil,
              evidence.opportunityId == nil,
              evidence.updatedAt == plan.expectedServerUpdatedAt,
              evidence.childRelationships.allSatisfy({ $0.opportunityId == nil }),
              evidence.contentFingerprint == plan.contentFingerprint else {
            throw HistoricalSiteVisitSettlementError.completedContentMismatch
        }
    }
}

@MainActor
private enum HistoricalSiteVisitSettlementLocalMutation {
    static func rearmActivePacket(
        plan: HistoricalSiteVisitSettlementPlan,
        in context: ModelContext
    ) throws {
        let operations = try exactOperations(plan: plan, context: context)
        guard !operations.contains(where: { $0.status == "inProgress" }) else {
            throw HistoricalSiteVisitSettlementError.operationInFlight
        }
        try context.transaction {
            for operation in operations where operation.status != "completed" {
                operation.status = "pending"
                operation.retryCount = 0
                operation.lastError = nil
                operation.lastAttemptedAt = nil
                operation.completedAt = nil
                operation.serverConfirmedAt = nil
            }
        }
    }

    static func settleCompletedPacket(
        plan: HistoricalSiteVisitSettlementPlan,
        in context: ModelContext,
        now: Date
    ) throws {
        let graph = try graph(plan: plan, context: context)
        let operations = try exactOperations(plan: plan, context: context)
        guard graph.visit.status == .completed,
              canonical(graph.visit.opportunityId ?? "") == plan.targetOpportunityId,
              graph.childrenAllTarget(plan.targetOpportunityId),
              !operations.contains(where: { $0.status == "inProgress" }) else {
            throw HistoricalSiteVisitSettlementError.phoneRelationshipConflict
        }

        try context.transaction {
            graph.visit.opportunityId = nil
            graph.visit.needsSync = false
            graph.visit.lastSyncedAt = plan.expectedServerUpdatedAt
            for artifact in graph.artifacts {
                artifact.opportunityId = nil
                artifact.needsSync = false
                artifact.lastSyncedAt = plan.expectedServerUpdatedAt
            }
            for answer in graph.answers {
                answer.opportunityId = nil
                answer.needsSync = false
                answer.lastSyncedAt = plan.expectedServerUpdatedAt
            }
            for draft in graph.drafts {
                draft.opportunityId = nil
                draft.needsSync = false
                draft.lastSyncedAt = plan.expectedServerUpdatedAt
            }
            for operation in operations {
                operation.status = "completed"
                operation.retryCount = 0
                operation.lastError = nil
                operation.lastAttemptedAt = nil
                operation.completedAt = now
                // Historical accounting is explicit: no server write confirmed
                // this queue operation. The content proof lives in the receipt.
                operation.serverConfirmedAt = nil
            }
        }
    }

    static func isApplied(
        plan: HistoricalSiteVisitSettlementPlan,
        in context: ModelContext
    ) throws -> Bool {
        guard plan.outcome == .settleCompletedHistory else { return false }
        let graph = try graph(plan: plan, context: context)
        let operations = try exactOperations(plan: plan, context: context)
        return graph.visit.opportunityId == nil
            && graph.visit.needsSync == false
            && graph.childrenAllUnlinkedAndClean
            && operations.allSatisfy {
                $0.status == "completed" && $0.serverConfirmedAt == nil
            }
    }

    private struct Graph {
        let visit: SiteVisit
        let artifacts: [SiteVisitCaptureArtifact]
        let answers: [SiteVisitChecklistAnswer]
        let drafts: [SiteVisitIdentityDraft]

        func childrenAllTarget(_ targetId: String) -> Bool {
            artifacts.allSatisfy { canonical($0.opportunityId ?? "") == targetId }
                && answers.allSatisfy { canonical($0.opportunityId ?? "") == targetId }
                && drafts.allSatisfy { canonical($0.opportunityId ?? "") == targetId }
        }

        var childrenAllUnlinkedAndClean: Bool {
            artifacts.allSatisfy { $0.opportunityId == nil && !$0.needsSync }
                && answers.allSatisfy { $0.opportunityId == nil && !$0.needsSync }
                && drafts.allSatisfy { $0.opportunityId == nil && !$0.needsSync }
        }
    }

    private static func graph(
        plan: HistoricalSiteVisitSettlementPlan,
        context: ModelContext
    ) throws -> Graph {
        let visits = try context.fetch(FetchDescriptor<SiteVisit>()).filter {
            canonical($0.id) == plan.visitId && canonical($0.companyId) == plan.companyId
        }
        guard visits.count == 1, let visit = visits.first else {
            throw HistoricalSiteVisitSettlementError.invalidIdentity
        }
        return Graph(
            visit: visit,
            artifacts: try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>()).filter {
                canonical($0.siteVisitId) == plan.visitId
                    && canonical($0.companyId) == plan.companyId
            },
            answers: try context.fetch(FetchDescriptor<SiteVisitChecklistAnswer>()).filter {
                canonical($0.siteVisitId) == plan.visitId
                    && canonical($0.companyId) == plan.companyId
            },
            drafts: try context.fetch(FetchDescriptor<SiteVisitIdentityDraft>()).filter {
                canonical($0.siteVisitId) == plan.visitId
                    && canonical($0.companyId) == plan.companyId
            }
        )
    }

    private static func exactOperations(
        plan: HistoricalSiteVisitSettlementPlan,
        context: ModelContext
    ) throws -> [SyncOperation] {
        let expected = Set(plan.operationIds)
        let matches = try context.fetch(FetchDescriptor<SyncOperation>()).filter {
            expected.contains($0.id.uuidString.lowercased())
        }
        guard matches.count == expected.count,
              matches.allSatisfy({ operation in
                  guard let envelope = try? JSONDecoder().decode(
                      SiteVisitSyncOperation.Payload.self,
                      from: operation.payload
                  ) else { return false }
                  return SiteVisitOutboundSync.isSiteVisitOperation(operation)
                      && canonical(envelope.siteVisitId) == plan.visitId
                      && canonical(envelope.companyId) == plan.companyId
                      && canonical(envelope.entityId) == canonical(operation.entityId)
              }) else {
            throw HistoricalSiteVisitSettlementError.malformedQueueEvidence
        }
        return matches
    }

    nonisolated private static func canonical(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
