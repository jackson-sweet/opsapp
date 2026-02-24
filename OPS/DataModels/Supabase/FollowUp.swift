//
//  FollowUp.swift
//  OPS
//
//  Scheduled reminder — Supabase-backed
//

import SwiftData
import Foundation

@Model
class FollowUp: Identifiable {
    @Attribute(.unique) var id: String
    var opportunityId: String
    var companyId: String
    var type: FollowUpType
    var status: FollowUpStatus
    var dueAt: Date
    var assignedTo: String?
    var notes: String?
    var createdAt: Date

    var isOverdue: Bool {
        status == .pending && dueAt < Date()
    }

    var isDueToday: Bool {
        status == .pending && Calendar.current.isDateInToday(dueAt)
    }

    init(
        id: String = UUID().uuidString,
        opportunityId: String,
        companyId: String,
        type: FollowUpType,
        dueAt: Date,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.opportunityId = opportunityId
        self.companyId = companyId
        self.type = type
        self.status = .pending
        self.dueAt = dueAt
        self.createdAt = createdAt
    }
}
