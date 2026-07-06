//
//  SiteVisit.swift
//  OPS
//
//  Scope assessment visit — Supabase-backed
//

import SwiftData
import Foundation

@Model
class SiteVisit: Identifiable {
    @Attribute(.unique) var id: String
    var opportunityId: String?
    var companyId: String
    var status: SiteVisitStatus
    var scheduledAt: Date?
    var completedAt: Date?
    var notes: String?
    var address: String?
    var assignedTo: String?
    var createdAt: Date

    /// The `activities` row id posted to the timeline when this visit was
    /// completed. LOCAL-ONLY (site visits never sync to Supabase) — its sole job
    /// is idempotency: once set, re-completing the visit (e.g. an offline retry)
    /// must NOT post a second "Site visit" activity. `nil` until a successful
    /// post; stays `nil` if the visit is unbound or the best-effort post fails.
    var loggedActivityId: String?

    init(
        id: String = UUID().uuidString,
        opportunityId: String? = nil,
        companyId: String,
        status: SiteVisitStatus = .scheduled,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.opportunityId = opportunityId
        self.companyId = companyId
        self.status = status
        self.createdAt = createdAt
    }
}
