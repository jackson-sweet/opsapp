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
    // Unified-activity parents — an activity can be parented to a lead
    // (opportunity), a client, OR a job (project). All nullable and additive
    // (mirrors the nullable call-provenance fields below): opportunity-only
    // rows carry nil clientId/projectId, and vice versa.
    var opportunityId: String?
    var clientId: String?             // DB: client_id (no FK)
    var projectId: String?            // DB: project_id (TEXT, no FK)
    var companyId: String
    var type: ActivityType
    var subject: String?              // backfilled by trg_activities_default_subject when omitted
    var bodyText: String?             // primary body field (DB: body_text)
    var content: String?              // legacy fallback (DB: content)
    var direction: String?            // "inbound" | "outbound" | nil
    var outcome: String?
    var durationMinutes: Int?

    // Around-call provenance (iOS lead capture, feature 154cb8a3). All nullable
    // and additive — older rows and web-authored rows carry nil.
    var callSource: String?           // how the call log was captured (DB: call_source)
    var callerNumber: String?         // normalized digits of the call's number (DB: caller_number)
    var callStartedAt: Date?          // best-effort call start (DB: call_started_at)

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
        opportunityId: String? = nil,
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
