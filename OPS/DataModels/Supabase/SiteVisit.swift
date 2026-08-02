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
    var projectId: String?
    var projectRef: String?
    var clientId: String?
    var clientRef: String?
    var status: SiteVisitStatus
    var scheduledAt: Date?
    var durationMinutes: Int = 60
    var assigneeIds: [String] = []
    var completedAt: Date?
    var notes: String?
    var internalNotes: String?
    var measurements: String?
    var photos: [String] = []
    var address: String?
    var assignedTo: String?
    var calendarEventId: String?
    var createdBy: String?
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?
    var needsSync: Bool = false
    var lastSyncedAt: Date?

    /// Local storage slot for the server-backed `site_visits.activity_id`.
    /// The guarded completion RPC owns creation and idempotency of that row.
    var loggedActivityId: String?

    init(
        id: String = UUID().uuidString.lowercased(),
        opportunityId: String? = nil,
        companyId: String,
        projectId: String? = nil,
        projectRef: String? = nil,
        clientId: String? = nil,
        clientRef: String? = nil,
        status: SiteVisitStatus = .scheduled,
        scheduledAt: Date? = nil,
        durationMinutes: Int = 60,
        assigneeIds: [String] = [],
        createdBy: String? = nil,
        loggedActivityId: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id.lowercased()
        self.opportunityId = opportunityId?.lowercased()
        self.companyId = companyId.lowercased()
        self.projectId = projectId?.lowercased()
        self.projectRef = projectRef?.lowercased()
        self.clientId = clientId?.lowercased()
        self.clientRef = clientRef?.lowercased()
        self.status = status
        self.scheduledAt = scheduledAt ?? createdAt
        self.durationMinutes = durationMinutes
        self.assigneeIds = assigneeIds.map { $0.lowercased() }
        self.createdBy = createdBy?.lowercased()
        self.loggedActivityId = loggedActivityId?.lowercased()
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.needsSync = true
    }
}
