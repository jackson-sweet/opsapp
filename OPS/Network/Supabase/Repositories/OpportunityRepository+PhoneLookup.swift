//
//  OpportunityRepository+PhoneLookup.swift
//  OPS
//
//  Around-call lead dedup (iOS feature 154cb8a3). When a call comes in or goes
//  out, the capture flow must attach to an existing lead instead of creating a
//  duplicate. The match runs against the LOCAL SwiftData cache — the
//  comprehensive set of synced opportunities — not the network, so it works
//  offline and instantly while the operator is mid-capture.
//

import Foundation
import SwiftData

extension OpportunityRepository {

    /// Find a synced lead whose `contactPhone` matches `phone` (after
    /// normalization). Reads the local SwiftData cache populated by sync.
    /// Returns the most-recently-active, non-deleted match, or `nil` when no
    /// lead carries that number.
    @MainActor
    func findByContactPhone(_ phone: String, in context: ModelContext) -> Opportunity? {
        let all = (try? context.fetch(FetchDescriptor<Opportunity>())) ?? []
        return Self.matchLead(phone: phone, candidates: all)
    }

    /// Pure dedup matcher — unit-testable without a `ModelContext`. Returns the
    /// live (non-deleted) opportunity whose `contactPhone` normalizes equal to
    /// `phone`, preferring the most-recently-active lead so the capture attaches
    /// to the deal the operator is actually working.
    static func matchLead(phone: String, candidates: [Opportunity]) -> Opportunity? {
        guard let target = PhoneNumber.normalize(phone) else { return nil }
        return candidates
            .filter { $0.deletedAt == nil }
            .sorted { ($0.lastActivityAt ?? $0.createdAt) > ($1.lastActivityAt ?? $1.createdAt) }
            .first { PhoneNumber.normalize($0.contactPhone) == target }
    }
}
