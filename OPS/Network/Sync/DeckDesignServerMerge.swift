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
                existing.needsSync = !pendingFields.isEmpty
            } else {
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                model.needsSync = false
                modelContext.insert(model)
            }
        }

        try modelContext.save()
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

    /// Fields of this design with a pending outbound write.
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

        var fields = Set<String>()
        for operation in all where operation.entityType == entityType
            && DeckDesign.canonicalUUIDString(operation.entityId) == canonicalId
            && operation.status == "pending" {
            fields.formUnion(operation.getChangedFields())
        }
        return fields
    }
}
