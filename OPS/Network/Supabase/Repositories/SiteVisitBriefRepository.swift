//
//  SiteVisitBriefRepository.swift
//  OPS
//
//  `public.read_site_visit_briefs(p_site_visit_ids uuid[])` — the narrow lead
//  projection a site-visit assignee may read (CREW SITE VISITS P1).
//
//  An assignee holds no `opportunities` grant, so the lead row itself stays
//  private (value, correspondence, notes). This RPC returns, for each
//  requested visit the caller can CURRENTLY read, the visit id, its lead id
//  and the lead's display fields — exactly the columns
//  `CalendarSiteVisitLeadDetails` mirrors. A requested id with no row means
//  the caller can no longer read that visit. Lead columns are null for a
//  leadless visit.
//

import Foundation
import Supabase

/// One row of `read_site_visit_briefs`.
struct SiteVisitBriefDTO: Decodable, Equatable, Sendable {
    let siteVisitId: String
    let opportunityId: String?
    let contactName: String?
    let title: String?
    let address: String?
    let aiSummary: String?
    let description: String?

    init(
        siteVisitId: String,
        opportunityId: String?,
        contactName: String?,
        title: String?,
        address: String?,
        aiSummary: String?,
        description: String?
    ) {
        self.siteVisitId = siteVisitId
        self.opportunityId = opportunityId
        self.contactName = contactName
        self.title = title
        self.address = address
        self.aiSummary = aiSummary
        self.description = description
    }

    enum CodingKeys: String, CodingKey {
        case siteVisitId = "site_visit_id"
        case opportunityId = "opportunity_id"
        case contactName = "contact_name"
        case title
        case address
        case aiSummary = "ai_summary"
        case description
    }
}

enum SiteVisitBriefRepositoryError: Error, Equatable {
    /// The server refuses more than `maxIdsPerRequest` distinct ids.
    case tooManyIds(Int)
}

enum SiteVisitBriefRepository {
    /// Server-side cap on distinct ids per call.
    static let maxIdsPerRequest = 200

    private struct Parameters: Encodable {
        let p_site_visit_ids: [String]
    }

    /// Reads the briefs for up to `maxIdsPerRequest` visit ids. Ids are
    /// canonicalized (trimmed, lowercased, de-duplicated) before the call;
    /// callers batch larger sets.
    static func fetchBriefs(siteVisitIds: [String]) async throws -> [SiteVisitBriefDTO] {
        let ids = canonicalIds(siteVisitIds)
        guard !ids.isEmpty else { return [] }
        guard ids.count <= maxIdsPerRequest else {
            throw SiteVisitBriefRepositoryError.tooManyIds(ids.count)
        }
        return try await SupabaseService.shared.client
            .rpc("read_site_visit_briefs", params: Parameters(p_site_visit_ids: ids))
            .execute()
            .value
    }

    static func canonicalIds(_ ids: [String]) -> [String] {
        Array(Set(
            ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )).sorted()
    }
}
