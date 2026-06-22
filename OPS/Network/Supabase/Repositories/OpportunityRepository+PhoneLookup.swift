//
//  OpportunityRepository+PhoneLookup.swift
//  OPS
//
//  Around-call lead dedup (iOS feature 154cb8a3). When a call is captured, OPS
//  must attach to an existing lead instead of minting a duplicate.
//
//  IMPORTANT: opportunities are NOT persisted to SwiftData — the pipeline list
//  is network-only (PipelineViewModel holds transient, unmanaged models; nothing
//  inserts Opportunity rows from sync). So dedup MUST hit the network to see
//  leads created on web or another device. The capture sheet fetches the
//  candidate set once when it opens, then matches locally (instant) as the
//  operator types, with a final network re-check before creating a new lead.
//

import Foundation

/// Minimal lead identity for phone dedup — decoupled from SwiftData/DTO so the
/// matcher stays pure and unit-testable.
struct LeadPhoneMatch: Equatable {
    let id: String
    let contactName: String
    let stageName: String?
    let phone: String?
    let recency: Date
}

extension OpportunityRepository {

    /// Fetch the company's (non-deleted) opportunities as dedup candidates.
    /// Returns an empty list on failure so the caller degrades to create-new.
    func fetchLeadCandidates() async -> [LeadPhoneMatch] {
        guard let dtos = try? await fetchAll() else { return [] }
        return dtos.map { dto in
            LeadPhoneMatch(
                id: dto.id,
                contactName: dto.contactName ?? "",
                stageName: dto.stage,
                phone: dto.contactPhone,
                recency: dto.lastActivityAt.flatMap { SupabaseDate.parse($0) }
                    ?? SupabaseDate.parse(dto.createdAt)
                    ?? Date.distantPast
            )
        }
    }

    /// Convenience: fetch + match in one call. Used as the final pre-create
    /// guard so a lead created since the sheet opened still attaches.
    func findByContactPhone(_ phone: String) async -> LeadPhoneMatch? {
        Self.matchLead(phone: phone, candidates: await fetchLeadCandidates())
    }

    /// Pure dedup matcher — unit-testable without network/SwiftData. Returns the
    /// candidate whose phone normalizes equal to `phone`, most-recently-active
    /// first. `fetchAll` already excludes soft-deleted leads.
    static func matchLead(phone: String, candidates: [LeadPhoneMatch]) -> LeadPhoneMatch? {
        guard let target = PhoneNumber.normalize(phone) else { return nil }
        return candidates
            .sorted {
                if $0.recency != $1.recency { return $0.recency > $1.recency }
                return $0.id < $1.id   // total order: same call always attaches to the same lead
            }
            .first { PhoneNumber.normalize($0.phone) == target }
    }
}
