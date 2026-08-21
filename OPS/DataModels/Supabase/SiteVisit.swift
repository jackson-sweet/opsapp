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

    /// Server-owned booking discriminator (`site_visits.booked_at`). Non-nil
    /// means this visit is a real appointment and `scheduledAt` is meaningful.
    /// Only the booking RPCs write it — the device converges, never authors.
    var bookedAt: Date?

    /// Per-booking heads-up override (`site_visits.reminder_lead_minutes`).
    /// NULL = the assignee's default lead applies. Server-owned, like `bookedAt`.
    var reminderLeadMinutes: Int?

    /// Server-owned Phase C appointment identity and presentation. These are
    /// nullable for every legacy/manual visit and never enter outbound edits.
    var appointmentHandoffId: String?
    var appointmentKind: String?
    var appointmentTitle: String?
    var appointmentLocation: String?

    /// Walk-up/legacy rows carry junk `scheduledAt` (defaulted to `createdAt`);
    /// every scheduling surface must gate on this, never on `status` alone.
    var isBookedAppointment: Bool { bookedAt != nil }

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
