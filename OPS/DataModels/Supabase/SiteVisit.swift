//
//  SiteVisit.swift
//  OPS
//
//  Scope assessment visit — Supabase-backed
//

import SwiftData
import Foundation

@Model
class SiteVisit {
    @Attribute(.unique) var id: String
    var opportunityId: String
    var companyId: String
    var status: SiteVisitStatus
    var scheduledAt: Date?
    var completedAt: Date?
    var notes: String?
    var address: String?
    var assignedTo: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        opportunityId: String,
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
