//
//  DeckDesignServerMerge.swift
//  OPS
//
//  One inbound merge for deck-design self-repair fetches. Extracted from
//  DeckTabView (bug 2fa645a8 hardening) so the lead dossier's DECK row and
//  the deck viewport repair the SAME way: pending local edits are protected,
//  id matching is canonical-UUID aware, and — critically — the pending-work
//  lookup never runs a #Predicate fetch of SyncOperation.
//

import Foundation
import SwiftData

@MainActor
enum DeckDesignServerMerge {

    /// Upsert server rows into the local store, protecting any field with a
    /// pending outbound write. Mirrors the inbound conflict rule DeckTabView
    /// shipped with the 2026-08-19 watchdog repair.
    static func merge(
        _ dtos: [SupabaseDeckDesignDTO],
        into modelContext: ModelContext
    ) throws {
        for dto in dtos {
            let pendingFields = pendingFields(for: dto.id, in: modelContext)
            let acceptedFields = Set(DeckDesign.serverMergeFields).subtracting(pendingFields)

            if let existing = try localDesign(matching: dto.id, in: modelContext) {
                existing.applyServerSnapshot(dto, accepting: acceptedFields)
                existing.lastSyncedAt = Date()
                // A row holding content the server has not confirmed stays
                // flagged even with no outstanding operation — clearing it
                // there disarms the conflict guard for an edit that was never
                // delivered. Bug 9f4aeaf8.
                existing.needsSync = !pendingFields.isEmpty || existing.hasUnsyncedDrawing
            } else {
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                model.needsSync = false
                modelContext.insert(model)
            }
        }

        try modelContext.save()
    }

    /// Moves a design's merge base to the payload a confirmed push delivered.
    ///
    /// This is the only thing that legitimately advances `syncedDrawingJSON`
    /// from the outbound side, and it is what lets a row that was protected
    /// mid-session start accepting inbound geometry again once its own work has
    /// actually reached the server. Bug 9f4aeaf8.
    ///
    /// The base moves ONLY when the design's current payload still equals the
    /// one that was pushed. If the user edited again while the push was in
    /// flight, the server has not seen that edit and the base must stay put.
    ///
    /// `nonisolated` because both outbound completion paths call it — the
    /// MainActor `OutboundProcessor` and the `@ModelActor` `DataActor` — each
    /// with its own context. Predicate-free for the same reason
    /// ``pendingFields(for:in:)`` is.
    nonisolated static func recordConfirmedPush(
        for operation: SyncOperation,
        in context: ModelContext
    ) throws {
        guard operation.entityType == SyncEntityType.deckDesign.rawValue else { return }
        guard ["create", "update"].contains(operation.operationType) else { return }
        guard
            let payload = try? JSONSerialization.jsonObject(with: operation.payload) as? [String: Any],
            let pushedDrawing = payload["drawing_data"],
            let pushedJSON = canonicalJSON(pushedDrawing)
        else { return }

        let canonicalId = DeckDesign.canonicalUUIDString(operation.entityId)
        let designs = try context.fetch(FetchDescriptor<DeckDesign>())
            .filter { DeckDesign.canonicalUUIDString($0.id) == canonicalId }

        for design in designs {
            guard let localJSON = canonicalJSON(jsonString: design.drawingDataJSON) else { continue }
            guard localJSON == pushedJSON else { continue }
            design.markDrawingSynced()
        }
    }

    /// Re-serializes a decoded JSON value with sorted keys so two payloads that
    /// carry the same content compare equal regardless of how each was written.
    private nonisolated static func canonicalJSON(_ object: Any) -> String? {
        guard
            JSONSerialization.isValidJSONObject(object),
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private nonisolated static func canonicalJSON(jsonString: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(jsonString.utf8)) else {
            return nil
        }
        return canonicalJSON(object)
    }

    /// Case-variant-aware local lookup — two spellings of one UUID are one row.
    static func localDesign(
        matching id: String,
        in modelContext: ModelContext
    ) throws -> DeckDesign? {
        let canonicalId = DeckDesign.canonicalUUIDString(id)
        let lowercasedId = canonicalId.lowercased()
        let uppercasedId = canonicalId.uppercased()
        let exactDescriptor = FetchDescriptor<DeckDesign>(
            predicate: #Predicate {
                $0.id == canonicalId || $0.id == lowercasedId || $0.id == uppercasedId
            }
        )

        if let exactMatch = try modelContext.fetch(exactDescriptor).first {
            return exactMatch
        }

        let allDescriptor = FetchDescriptor<DeckDesign>()
        return try modelContext.fetch(allDescriptor).first {
            DeckDesign.canonicalUUIDString($0.id) == canonicalId
        }
    }

    /// Fields of this design an inbound merge must keep local.
    ///
    /// Delegates the decision to ``SyncFieldGuard``, which is the single source
    /// of truth the InboundProcessor, RealtimeProcessor and DataActor deck
    /// branches already use. This function used to match `status == "pending"`
    /// alone, so it silently lost the in-flight, just-completed, failed and
    /// parked coverage its siblings get — the doc comment claimed to mirror the
    /// inbound conflict rule while protecting strictly less than it. An op that
    /// flipped to `inProgress` immediately before the network call, or that
    /// parked on a 0-row PATCH, protected nothing at all. Bug 9f4aeaf8.
    ///
    /// Deliberately predicate-free, filtered in Swift.
    ///
    /// A `#Predicate` fetch of `SyncOperation` TRAPS (EXC_BREAKPOINT inside
    /// SwiftData, not a thrown error) against a store whose operation table
    /// has never held a row — reproducible in every fresh in-memory
    /// container, and reachable in production on a first-run device whose
    /// deck arrives through the self-repair fetch. `try?` does not catch it.
    /// Same contract as `ProjectCacheMerge.operations`.
    ///
    /// The cost is bounded: this runs once per repair fetch, never per
    /// realtime event.
    static func pendingFields(
        for id: String,
        in modelContext: ModelContext
    ) -> Set<String> {
        let entityType = SyncEntityType.deckDesign.rawValue
        let canonicalId = DeckDesign.canonicalUUIDString(id)

        guard let all = try? modelContext.fetch(FetchDescriptor<SyncOperation>()) else {
            return []
        }

        let operations = all.filter {
            $0.entityType == entityType
                && DeckDesign.canonicalUUIDString($0.entityId) == canonicalId
        }
        return SyncFieldGuard.protectedFields(from: operations, now: Date())
    }
}
