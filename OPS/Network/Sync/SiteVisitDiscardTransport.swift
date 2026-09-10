import Foundation
import SwiftData
import Supabase

struct SiteVisitDiscardIntent: Codable, Equatable {
    let capture: SiteVisitWriteJSON
    let discardedAt: String
    let supersededOperationIds: [UUID]
}
struct SiteVisitDiscardReceipt: Codable, Equatable {
    let commandId: UUID
    let companyId: String
    let siteVisitId: String
    let discardedAt: String
    let outcome: String
    enum CodingKeys: String, CodingKey {
        case commandId = "command_id", companyId = "company_id", siteVisitId = "site_visit_id", discardedAt = "discarded_at", outcome
    }
}
enum SiteVisitDiscardTransport {
    typealias Deliver = (UUID, SiteVisitDiscardIntent, String) async throws -> SiteVisitDiscardReceipt
    @MainActor
    static func deliver(_ id: UUID, _ intent: SiteVisitDiscardIntent, _ actor: String) async throws -> SiteVisitDiscardReceipt {
        struct Parameters: Encodable {
            let p_command_id: UUID; let p_capture: SiteVisitWriteJSON
            let p_discarded_at: String; let p_expected_actor: String
        }
        return try await SupabaseService.shared.client.rpc("discard_site_visit_capture", params: Parameters(
            p_command_id: id, p_capture: intent.capture, p_discarded_at: intent.discardedAt, p_expected_actor: actor)).execute().value
    }
    static func accept(_ receipt: SiteVisitDiscardReceipt, operation: SyncOperation, intent: SiteVisitDiscardIntent,
                       actor: String, context: ModelContext) throws {
        guard receipt.commandId == operation.id, receipt.outcome == "discarded",
              receipt.companyId == intent.capture["company_id"]?.string,
              receipt.siteVisitId == intent.capture["id"]?.string,
              let actual = SupabaseDate.parse(receipt.discardedAt), let expected = SupabaseDate.parse(intent.discardedAt),
              abs(actual.timeIntervalSince(expected)) < 0.001 else { throw SiteVisitWriteError.invalidReceipt }
        let fresh = ModelContext(context.container)
        let id = operation.id
        guard let current = try fresh.fetch(FetchDescriptor<SyncOperation>(predicate: #Predicate { $0.id == id })).first,
              current.payload == operation.payload, current.siteVisitWriteActorId == actor else { throw CancellationError() }
        let data = try JSONEncoder().encode(receipt)
        let originalIds = Set(intent.supersededOperationIds)
        try fresh.transaction {
            current.siteVisitWriteReceiptData = data
            for old in try fresh.fetch(FetchDescriptor<SyncOperation>()) where originalIds.contains(old.id) {
                guard old.siteVisitWriteActorId == nil || old.siteVisitWriteActorId == actor else { continue }
                old.status = "completed"; old.completedAt = Date()
            }
            let visitId = receipt.siteVisitId
            if let visit = try fresh.fetch(FetchDescriptor<SiteVisit>(predicate: #Predicate { $0.id == visitId })).first,
               visit.deletedAt.map(SupabaseDate.format) == intent.discardedAt {
                visit.needsSync = false; visit.lastSyncedAt = Date()
            }
            for row in try fresh.fetch(FetchDescriptor<SiteVisitCaptureArtifact>(predicate: #Predicate { $0.siteVisitId == visitId })) where row.deletedAt.map(SupabaseDate.format) == intent.discardedAt { row.needsSync = false; row.lastSyncedAt = Date() }
            for row in try fresh.fetch(FetchDescriptor<SiteVisitChecklistAnswer>(predicate: #Predicate { $0.siteVisitId == visitId })) where row.deletedAt.map(SupabaseDate.format) == intent.discardedAt { row.needsSync = false; row.lastSyncedAt = Date() }
            for row in try fresh.fetch(FetchDescriptor<SiteVisitIdentityDraft>(predicate: #Predicate { $0.siteVisitId == visitId })) where row.deletedAt.map(SupabaseDate.format) == intent.discardedAt { row.needsSync = false; row.lastSyncedAt = Date() }
        }
        // Keep registered operations consistent with the owning drain's next save.
        for old in try fresh.fetch(FetchDescriptor<SyncOperation>()) where originalIds.contains(old.id) {
            let registered: SyncOperation? = context.registeredModel(for: old.persistentModelID)
            registered?.status = old.status; registered?.completedAt = old.completedAt
            registered?.siteVisitWriteReceiptData = old.siteVisitWriteReceiptData
        }
        operation.siteVisitWriteReceiptData = data
    }
}
