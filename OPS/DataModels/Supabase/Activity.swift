//
//  Activity.swift
//  OPS
//
//  Timeline event per opportunity — Supabase-backed.
//  Phase 1 fields cover note/call/email/stage_change. Defers email-thread
//  metadata (cc_emails, email_message_id, etc.) and classifier fields.
//

import SwiftData
import Foundation

@Model
class Activity: Identifiable {
    @Attribute(.unique) var id: String
    var opportunityId: String
    var companyId: String
    var type: ActivityType
    var subject: String?              // backfilled by trg_activities_default_subject when omitted
    var bodyText: String?             // primary body field (DB: body_text)
    var content: String?              // legacy fallback (DB: content)
    var direction: String?            // "inbound" | "outbound" | nil
    var outcome: String?
    var durationMinutes: Int?
    var isRead: Bool
    var hasAttachments: Bool
    var attachmentCount: Int
    var createdBy: String?
    var createdAt: Date

    /// Display body — prefers bodyText, falls back to content (for legacy rows).
    var displayBody: String? {
        if let bodyText, !bodyText.isEmpty { return bodyText }
        return content
    }

    init(
        id: String = UUID().uuidString,
        opportunityId: String,
        companyId: String,
        type: ActivityType,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.opportunityId = opportunityId
        self.companyId = companyId
        self.type = type
        self.isRead = false
        self.hasAttachments = false
        self.attachmentCount = 0
        self.createdAt = createdAt
    }
}
