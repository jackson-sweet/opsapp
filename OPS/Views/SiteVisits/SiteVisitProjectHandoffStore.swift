//
//  SiteVisitProjectHandoffStore.swift
//  OPS
//
//  In-memory bridge between site-visit review and lead conversion.
//

import Foundation

@MainActor
final class SiteVisitProjectHandoffStore {
    static let shared = SiteVisitProjectHandoffStore()

    private var pendingPayloadsByOpportunityId: [String: SiteVisitProjectPayload] = [:]

    private init() {}

    func stage(_ payload: SiteVisitProjectPayload, for opportunityId: String) {
        pendingPayloadsByOpportunityId[opportunityId] = payload
    }

    func consume(for opportunityId: String) -> SiteVisitProjectPayload? {
        pendingPayloadsByOpportunityId.removeValue(forKey: opportunityId)
    }
}
