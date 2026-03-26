//
//  NotificationPreferencesDTO.swift
//  OPS
//
//  Data Transfer Object for the notification_preferences Supabase table.
//  Maps channel_preferences JSONB to [String: ChannelToggle].
//

import Foundation

/// Per-channel toggle for a single event type (push and email independently)
struct ChannelToggle: Codable, Equatable {
    var push: Bool
    var email: Bool
}

/// All known event types that can have per-channel preferences.
/// Must stay in sync with the web app's EventType union and the DB default JSONB.
enum NotificationEventType: String, CaseIterable, Codable {
    case taskAssigned = "task_assigned"
    case taskCompleted = "task_completed"
    case scheduleChanges = "schedule_changes"
    case projectUpdates = "project_updates"
    case expenseSubmitted = "expense_submitted"
    case expenseApproved = "expense_approved"
    case invoiceSent = "invoice_sent"
    case paymentReceived = "payment_received"
    case teamMentions = "team_mentions"
    case dailyDigest = "daily_digest"

    /// Human-readable display name for the settings UI
    var displayName: String {
        switch self {
        case .taskAssigned:      return "Task Assignments"
        case .taskCompleted:     return "Task Completed"
        case .scheduleChanges:   return "Schedule Changes"
        case .projectUpdates:    return "Project Updates"
        case .expenseSubmitted:  return "Expense Submitted"
        case .expenseApproved:   return "Expense Approved"
        case .invoiceSent:       return "Invoice Sent"
        case .paymentReceived:   return "Payment Received"
        case .teamMentions:      return "Team Mentions"
        case .dailyDigest:       return "Daily Digest"
        }
    }

    /// Short description for the settings UI
    var displayDescription: String {
        switch self {
        case .taskAssigned:      return "When you're assigned to a task"
        case .taskCompleted:     return "When a task is marked complete"
        case .scheduleChanges:   return "When project dates change"
        case .projectUpdates:    return "General project activity"
        case .expenseSubmitted:  return "When an expense is submitted for review"
        case .expenseApproved:   return "When your expense is approved"
        case .invoiceSent:       return "When an invoice is sent to a client"
        case .paymentReceived:   return "When a payment is received"
        case .teamMentions:      return "When someone mentions you"
        case .dailyDigest:       return "Daily summary of activity"
        }
    }
}

/// Default channel preferences for new users — mirrors DB column default and web app defaults.
let defaultChannelPreferences: [String: ChannelToggle] = {
    var prefs: [String: ChannelToggle] = [:]
    for eventType in NotificationEventType.allCases {
        switch eventType {
        case .projectUpdates, .expenseSubmitted, .expenseApproved, .paymentReceived:
            prefs[eventType.rawValue] = ChannelToggle(push: true, email: true)
        case .dailyDigest:
            prefs[eventType.rawValue] = ChannelToggle(push: false, email: false)
        default:
            prefs[eventType.rawValue] = ChannelToggle(push: true, email: false)
        }
    }
    return prefs
}()

/// Full DTO matching the notification_preferences Supabase row.
struct NotificationPreferencesDTO: Codable, Equatable {
    let id: String?
    let userId: String
    let companyId: String
    var pushEnabled: Bool
    var emailEnabled: Bool
    var channelPreferences: [String: ChannelToggle]
    var quietHoursStart: String?
    var quietHoursEnd: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId             = "user_id"
        case companyId          = "company_id"
        case pushEnabled        = "push_enabled"
        case emailEnabled       = "email_enabled"
        case channelPreferences = "channel_preferences"
        case quietHoursStart    = "quiet_hours_start"
        case quietHoursEnd      = "quiet_hours_end"
        case createdAt          = "created_at"
        case updatedAt          = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        companyId = try container.decode(String.self, forKey: .companyId)
        pushEnabled = try container.decodeIfPresent(Bool.self, forKey: .pushEnabled) ?? true
        emailEnabled = try container.decodeIfPresent(Bool.self, forKey: .emailEnabled) ?? true
        quietHoursStart = try container.decodeIfPresent(String.self, forKey: .quietHoursStart)
        quietHoursEnd = try container.decodeIfPresent(String.self, forKey: .quietHoursEnd)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)

        // Decode channel_preferences JSONB with fallback to defaults for missing keys
        let raw = try container.decodeIfPresent([String: ChannelToggle].self, forKey: .channelPreferences)
        var merged = defaultChannelPreferences
        if let raw {
            for (key, value) in raw {
                merged[key] = value
            }
        }
        channelPreferences = merged
    }

    /// Memberwise init for creating locally (e.g. optimistic defaults before Supabase responds)
    init(
        id: String? = nil,
        userId: String,
        companyId: String,
        pushEnabled: Bool = true,
        emailEnabled: Bool = true,
        channelPreferences: [String: ChannelToggle]? = nil,
        quietHoursStart: String? = nil,
        quietHoursEnd: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.companyId = companyId
        self.pushEnabled = pushEnabled
        self.emailEnabled = emailEnabled
        self.channelPreferences = channelPreferences ?? defaultChannelPreferences
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Convenience Accessors

    /// Get toggle for a specific event type, falling back to defaults if missing
    func toggle(for eventType: NotificationEventType) -> ChannelToggle {
        channelPreferences[eventType.rawValue] ?? defaultChannelPreferences[eventType.rawValue] ?? ChannelToggle(push: true, email: false)
    }

    /// Check if push is enabled for a specific event type (respects global kill switch)
    func isPushEnabled(for eventType: NotificationEventType) -> Bool {
        guard pushEnabled else { return false }
        return toggle(for: eventType).push
    }

    /// Check if email is enabled for a specific event type (respects global kill switch)
    func isEmailEnabled(for eventType: NotificationEventType) -> Bool {
        guard emailEnabled else { return false }
        return toggle(for: eventType).email
    }
}
