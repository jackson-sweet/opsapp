import Foundation
import SwiftData

struct RecoveryAttentionSummary: Equatable, Sendable {
    var attentionCount = 0
    var anyParked = false
}

extension RecoveryInventory {
    /// The pill needs work-unit tones only: no names, manifests, answers,
    /// delivery history, member rows, timestamps, or orphan drawings. Joins
    /// deliberately mirror build(), including first-draft ownership.
    static func attentionSummary(
        ops: [SyncOpSnapshot],
        autocreates: [AutocreateSnapshot],
        photos: [PhotoSnapshot],
        drafts: [DraftSnapshot],
        deckArtifacts: [ArtifactSnapshot],
        quarantinedVisitIds: Set<String> = []
    ) -> RecoveryAttentionSummary {
        let live = ops.filter { ["pending", "inProgress", "failed", "parked"].contains($0.status) }
        var consumedOps = Set<UUID>()
        var consumedAutos = Set<String>()
        var consumedPhotos = Set<String>()
        var result = RecoveryAttentionSummary()
        func tone(_ status: String) -> Int {
            status == "parked" ? 2 : status == "failed" ? 1 : 0
        }
        func append(_ tone: Int) {
            if tone > 0 { result.attentionCount += 1 }
            if tone == 2 { result.anyParked = true }
        }
        for draft in drafts where !quarantinedVisitIds.contains(draft.siteVisitId.lowercased()) {
            let decks = Set(deckArtifacts.filter { $0.siteVisitId == draft.siteVisitId }.compactMap { $0.deckDesignId?.lowercased() })
            var worst = 0
            for op in live where !consumedOps.contains(op.id) {
                if op.siteVisitId == draft.siteVisitId.lowercased()
                    || (op.entityType == "client" && op.entityId.lowercased() == draft.clientId?.lowercased())
                    || (op.entityType == "deckDesign" && decks.contains(op.entityId.lowercased())) {
                    consumedOps.insert(op.id)
                    worst = max(worst, tone(op.status))
                }
            }
            if let clientId = draft.clientId?.lowercased(), !clientId.isEmpty,
               let request = autocreates.first(where: { $0.clientId.lowercased() == clientId && !consumedAutos.contains(clientId) }) {
                consumedAutos.insert(clientId)
                worst = max(worst, request.isParked ? 2 : request.attempts > 0 ? 1 : 0)
            }
            if let leadId = draft.opportunityId?.lowercased(), !leadId.isEmpty {
                for photo in photos where photo.entityId.lowercased() == leadId && !consumedPhotos.contains(photo.id) {
                    consumedPhotos.insert(photo.id)
                    worst = max(worst, photo.status == "failed" ? 1 : 0)
                }
            }
            append(worst)
        }
        let packets = Dictionary(grouping: live.filter { !consumedOps.contains($0.id) && $0.siteVisitId != nil }, by: { $0.siteVisitId! })
        for packet in packets.values {
            append(packet.map { tone($0.status) }.max() ?? 0)
            consumedOps.formUnion(packet.map(\.id))
        }
        for op in live where !consumedOps.contains(op.id) { append(tone(op.status)) }
        for request in autocreates where !consumedAutos.contains(request.clientId.lowercased()) {
            append(request.isParked ? 2 : request.attempts > 0 ? 1 : 0)
        }
        for group in Dictionary(grouping: photos.filter { !consumedPhotos.contains($0.id) }, by: \.entityId).values {
            append(group.contains { $0.status == "failed" } ? 1 : 0)
        }
        return result
    }
}

/// Construct off MainActor. This context is read-only and never receives live
/// main-context models. Fresh context per snapshot avoids stale registrations.
enum RecoveryAttentionReader {
    static func read(
        container: ModelContainer,
        companyId: String,
        autocreates: [AutocreateSnapshot],
        quarantinedVisitIds: Set<String>
    ) throws -> RecoveryAttentionSummary {
        let signposter = CapturePerformanceTrace.signposter
        let span = signposter.beginInterval("RecoveryAttentionRead", id: signposter.makeSignpostID())
        defer { signposter.endInterval("RecoveryAttentionRead", span) }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let ops = try RecoveryStoreQueries.activeOperations(in: context).filter { operation in
            guard SiteVisitOutboundSync.isSiteVisitOperation(operation) else { return true }
            guard let payload = try? JSONDecoder().decode(SiteVisitSyncOperation.Payload.self, from: operation.payload) else { return false }
            return payload.companyId.lowercased() == companyId
        }.map(SyncOpSnapshot.init(from:))
        let photos = try context.fetch(FetchDescriptor<LocalPhoto>(predicate: #Predicate {
            $0.status == "failed" || $0.status == "local"
        })).map(PhotoSnapshot.init(from:))
        if !ops.contains(where: { $0.status == "failed" || $0.status == "parked" }),
           !autocreates.contains(where: { $0.isParked || $0.attempts > 0 }),
           !photos.contains(where: { $0.status == "failed" }) {
            return RecoveryAttentionSummary()
        }
        let lower = companyId.lowercased()
        let upper = companyId.uppercased()
        let drafts = try context.fetch(FetchDescriptor<SiteVisitIdentityDraft>(predicate: #Predicate {
            ($0.companyId == lower || $0.companyId == upper) && ($0.opportunityId == nil || $0.lastCommittedAt == nil)
        })).map(DraftSnapshot.init(from:))
        // Deck artifacts alone affect grouping. Checklist answers and photo
        // artifacts affect detail counts, never the attention count.
        let deckIds = RecoveryStoreQueries.caseVariants(Set(ops.filter { $0.entityType == "deckDesign" }.map(\.entityId)))
        let artifacts: [ArtifactSnapshot]
        if deckIds.isEmpty || drafts.isEmpty {
            artifacts = []
        } else {
            // Bug 7a726160 — this predicate used `deckIds.contains($0.deckDesignId ?? "")`.
            // SwiftData lowers `??` to a TERNARY that Core Data's SQL generator
            // rejects ("unimplemented SQL generation for predicate … (bad LHS)"),
            // and the rejection is an Objective-C exception inside
            // `performAndWait` — uncatchable from Swift, so it aborted the
            // process on the utility thread this reader runs on. It fired only
            // once something needed attention (a backgrounded upload failing was
            // enough), which is why every home-swipe killed the app. Fetch the
            // company's deck-bound artifacts with a nil test the store can
            // compile, then match ids in Swift.
            artifacts = try context.fetch(FetchDescriptor<SiteVisitCaptureArtifact>(predicate: #Predicate {
                $0.deletedAt == nil && ($0.companyId == lower || $0.companyId == upper)
                    && $0.deckDesignId != nil
            }))
            .filter { artifact in
                guard let deckDesignId = artifact.deckDesignId else { return false }
                return deckIds.contains(deckDesignId)
            }
            .map(ArtifactSnapshot.init(from:))
        }
        return RecoveryInventory.attentionSummary(
            ops: ops, autocreates: autocreates, photos: photos, drafts: drafts,
            deckArtifacts: artifacts, quarantinedVisitIds: quarantinedVisitIds
        )
    }
}
