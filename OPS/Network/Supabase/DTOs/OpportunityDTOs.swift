//
//  OpportunityDTOs.swift
//  OPS
//
//  Data Transfer Objects for Pipeline/Opportunity Supabase tables.
//  Schema parity verified 2026-05-07 against public.opportunities, activities,
//  follow_ups, stage_transitions.
//

import Foundation

// MARK: - Opportunity

struct OpportunityDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let title: String?
    let contactName: String?
    let contactEmail: String?
    let contactPhone: String?
    let description: String?
    let address: String?

    let stage: String
    let stageEnteredAt: String
    let stageManuallySet: Bool?
    let assignedTo: String?
    let priority: String?
    let source: String?
    let quoteDeliveryMethod: String?

    let estimatedValue: Double?
    let actualValue: Double?
    let winProbability: Int?

    let expectedCloseDate: String?
    let actualCloseDate: String?
    let nextFollowUpAt: String?
    let lastActivityAt: String?

    let projectId: String?
    let clientId: String?
    let lostReason: String?
    let lostNotes: String?

    let deletedAt: String?
    let archivedAt: String?

    let tags: [String]?
    let sourceEmailId: String?

    let correspondenceCount: Int?
    let outboundCount: Int?
    let inboundCount: Int?
    let lastInboundAt: String?
    let lastOutboundAt: String?
    let lastMessageDirection: String?

    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case companyId            = "company_id"
        case title
        case contactName          = "contact_name"
        case contactEmail         = "contact_email"
        case contactPhone         = "contact_phone"
        case description
        case address
        case stage
        case stageEnteredAt       = "stage_entered_at"
        case stageManuallySet     = "stage_manually_set"
        case assignedTo           = "assigned_to"
        case priority
        case source
        case quoteDeliveryMethod  = "quote_delivery_method"
        case estimatedValue       = "estimated_value"
        case actualValue          = "actual_value"
        case winProbability       = "win_probability"
        case expectedCloseDate    = "expected_close_date"
        case actualCloseDate      = "actual_close_date"
        case nextFollowUpAt       = "next_follow_up_at"
        case lastActivityAt       = "last_activity_at"
        case projectId            = "project_id"
        case clientId             = "client_id"
        case lostReason           = "lost_reason"
        case lostNotes            = "lost_notes"
        case deletedAt            = "deleted_at"
        case archivedAt           = "archived_at"
        case tags
        case sourceEmailId        = "source_email_id"
        case correspondenceCount  = "correspondence_count"
        case outboundCount        = "outbound_count"
        case inboundCount         = "inbound_count"
        case lastInboundAt        = "last_inbound_at"
        case lastOutboundAt       = "last_outbound_at"
        case lastMessageDirection = "last_message_direction"
        case createdAt            = "created_at"
        case updatedAt            = "updated_at"
    }

    func toModel() -> Opportunity {
        let opp = Opportunity(
            id: id,
            companyId: companyId,
            contactName: contactName ?? "",
            stage: PipelineStage(rawValue: stage) ?? .newLead,
            stageEnteredAt: SupabaseDate.parse(stageEnteredAt) ?? Date(),
            createdAt: SupabaseDate.parse(createdAt) ?? Date(),
            updatedAt: SupabaseDate.parse(updatedAt) ?? Date()
        )
        opp.title = title
        opp.contactEmail = contactEmail
        opp.contactPhone = contactPhone
        opp.descriptionText = description
        opp.address = address
        opp.stageManuallySet = stageManuallySet ?? false
        opp.assignedTo = assignedTo
        opp.priority = priority
        opp.source = source
        if let m = quoteDeliveryMethod { opp.quoteDeliveryMethod = QuoteDeliveryMethod(rawValue: m) }
        opp.estimatedValue = estimatedValue
        opp.actualValue = actualValue
        opp.winProbabilityOverride = winProbability
        opp.expectedCloseDate = expectedCloseDate.flatMap { SupabaseDate.parse($0) }
        opp.actualCloseDate = actualCloseDate.flatMap { SupabaseDate.parse($0) }
        opp.nextFollowUpAt = nextFollowUpAt.flatMap { SupabaseDate.parse($0) }
        opp.lastActivityAt = lastActivityAt.flatMap { SupabaseDate.parse($0) }
        opp.projectId = projectId
        opp.clientId = clientId
        opp.lostReason = lostReason
        opp.lostNotes = lostNotes
        opp.deletedAt = deletedAt.flatMap { SupabaseDate.parse($0) }
        opp.archivedAt = archivedAt.flatMap { SupabaseDate.parse($0) }
        opp.tags = tags ?? []
        opp.sourceEmailId = sourceEmailId
        opp.correspondenceCount = correspondenceCount ?? 0
        opp.outboundCount = outboundCount ?? 0
        opp.inboundCount = inboundCount ?? 0
        opp.lastInboundAt = lastInboundAt.flatMap { SupabaseDate.parse($0) }
        opp.lastOutboundAt = lastOutboundAt.flatMap { SupabaseDate.parse($0) }
        opp.lastMessageDirection = lastMessageDirection
        return opp
    }
}

struct CreateOpportunityDTO: Codable {
    let companyId: String
    let title: String?               // optional — DB trigger backfills from contact_name
    let contactName: String
    let contactEmail: String?
    let contactPhone: String?
    let description: String?
    let address: String?
    let estimatedValue: Double?
    let source: String?
    let priority: String?
    let assignedTo: String?
    let expectedCloseDate: String?
    let quoteDeliveryMethod: String?
    let clientId: String?

    init(
        companyId: String,
        title: String? = nil,
        contactName: String,
        contactEmail: String? = nil,
        contactPhone: String? = nil,
        description: String? = nil,
        address: String? = nil,
        estimatedValue: Double? = nil,
        source: String? = nil,
        priority: String? = nil,
        assignedTo: String? = nil,
        expectedCloseDate: Date? = nil,
        quoteDeliveryMethod: String? = nil,
        clientId: String? = nil
    ) {
        self.companyId = companyId
        self.title = title
        self.contactName = contactName
        self.contactEmail = contactEmail
        self.contactPhone = contactPhone
        self.description = description
        self.address = address
        self.estimatedValue = estimatedValue
        self.source = source
        self.priority = priority
        self.assignedTo = assignedTo
        self.expectedCloseDate = expectedCloseDate.map { SupabaseDate.formatDate($0) }
        self.quoteDeliveryMethod = quoteDeliveryMethod
        self.clientId = clientId
    }

    enum CodingKeys: String, CodingKey {
        case companyId            = "company_id"
        case title
        case contactName          = "contact_name"
        case contactEmail         = "contact_email"
        case contactPhone         = "contact_phone"
        case description
        case address
        case estimatedValue       = "estimated_value"
        case source
        case priority
        case assignedTo           = "assigned_to"
        case expectedCloseDate    = "expected_close_date"
        case quoteDeliveryMethod  = "quote_delivery_method"
        case clientId             = "client_id"
    }
}

struct UpdateOpportunityDTO: Codable {
    var title: String?
    var contactName: String?
    var contactEmail: String?
    var contactPhone: String?
    var description: String?
    var address: String?
    var estimatedValue: Double?
    var actualValue: Double?
    var source: String?
    var priority: String?
    var assignedTo: String?
    var expectedCloseDate: String?
    var actualCloseDate: String?
    var clientId: String?
    var projectId: String?
    var lostReason: String?
    var lostNotes: String?
    var quoteDeliveryMethod: String?
    var archivedAt: String?
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case title
        case contactName          = "contact_name"
        case contactEmail         = "contact_email"
        case contactPhone         = "contact_phone"
        case description
        case address
        case estimatedValue       = "estimated_value"
        case actualValue          = "actual_value"
        case source
        case priority
        case assignedTo           = "assigned_to"
        case expectedCloseDate    = "expected_close_date"
        case actualCloseDate      = "actual_close_date"
        case clientId             = "client_id"
        case projectId            = "project_id"
        case lostReason           = "lost_reason"
        case lostNotes            = "lost_notes"
        case quoteDeliveryMethod  = "quote_delivery_method"
        case archivedAt           = "archived_at"
        case deletedAt            = "deleted_at"
    }
}

// MARK: - Edit-form patch

/// Full-form edit patch for `EditLeadSheet`. Unlike `UpdateOpportunityDTO`
/// (whose synthesized `Codable` omits nil keys — correct for the partial
/// mark-won / mark-lost / archive patches), this ALWAYS emits its edit-managed
/// fields, including explicit JSON `null`, so clearing a field in the edit form
/// (e.g. deleting the phone number) actually persists instead of being silently
/// dropped by `encodeIfPresent`. Scoped to the edit path so it cannot regress
/// the partial updaters. (review I-12)
struct EditOpportunityPatch: Encodable {
    var title: String?
    var contactName: String
    var contactEmail: String?
    var contactPhone: String?
    var description: String?
    var address: String?
    var estimatedValue: Double?
    var source: String?
    var priority: String?

    enum CodingKeys: String, CodingKey {
        case title
        case contactName    = "contact_name"
        case contactEmail   = "contact_email"
        case contactPhone   = "contact_phone"
        case description
        case address
        case estimatedValue = "estimated_value"
        case source
        case priority
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // `encode` (NOT `encodeIfPresent`) so a nil emits explicit JSON null and
        // clears the column server-side. contactName is non-optional and the
        // form requires it non-empty, so it is never sent as null.
        try c.encode(title, forKey: .title)
        try c.encode(contactName, forKey: .contactName)
        try c.encode(contactEmail, forKey: .contactEmail)
        try c.encode(contactPhone, forKey: .contactPhone)
        try c.encode(description, forKey: .description)
        try c.encode(address, forKey: .address)
        try c.encode(estimatedValue, forKey: .estimatedValue)
        try c.encode(source, forKey: .source)
        try c.encode(priority, forKey: .priority)
    }
}

// MARK: - Activity

struct ActivityDTO: Codable, Identifiable {
    let id: String
    let opportunityId: String?
    let companyId: String
    let type: String
    let subject: String?
    let bodyText: String?
    let content: String?
    let direction: String?
    let outcome: String?
    let durationMinutes: Int?
    let isRead: Bool?
    let hasAttachments: Bool?
    let attachmentCount: Int?
    let createdBy: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case opportunityId   = "opportunity_id"
        case companyId       = "company_id"
        case type
        case subject
        case bodyText        = "body_text"
        case content
        case direction
        case outcome
        case durationMinutes = "duration_minutes"
        case isRead          = "is_read"
        case hasAttachments  = "has_attachments"
        case attachmentCount = "attachment_count"
        case createdBy       = "created_by"
        case createdAt       = "created_at"
    }

    func toModel() -> Activity {
        let act = Activity(
            id: id,
            opportunityId: opportunityId ?? "",
            companyId: companyId,
            type: ActivityType(rawValue: type) ?? .note,
            createdAt: SupabaseDate.parse(createdAt) ?? Date()
        )
        act.subject = subject
        act.bodyText = bodyText
        act.content = content
        act.direction = direction
        act.outcome = outcome
        act.durationMinutes = durationMinutes
        act.isRead = isRead ?? false
        act.hasAttachments = hasAttachments ?? false
        act.attachmentCount = attachmentCount ?? 0
        act.createdBy = createdBy
        return act
    }
}

struct CreateActivityDTO: Codable {
    let opportunityId: String
    let companyId: String
    let type: String
    let subject: String?    // optional — trg_activities_default_subject backfills
    let bodyText: String?
    let direction: String?
    let outcome: String?
    let durationMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case opportunityId   = "opportunity_id"
        case companyId       = "company_id"
        case type
        case subject
        case bodyText        = "body_text"
        case direction
        case outcome
        case durationMinutes = "duration_minutes"
    }
}

// MARK: - Follow-Up (BUG FIX: notes→description, add required title)

struct FollowUpDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let opportunityId: String?
    let clientId: String?
    let title: String
    let description: String?
    let type: String
    let status: String
    let dueAt: String
    let reminderAt: String?
    let assignedTo: String?
    let createdBy: String?
    let completedAt: String?
    let completionNotes: String?
    let isAutoGenerated: Bool?
    let triggerSource: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case companyId       = "company_id"
        case opportunityId   = "opportunity_id"
        case clientId        = "client_id"
        case title
        case description
        case type
        case status
        case dueAt           = "due_at"
        case reminderAt      = "reminder_at"
        case assignedTo      = "assigned_to"
        case createdBy       = "created_by"
        case completedAt     = "completed_at"
        case completionNotes = "completion_notes"
        case isAutoGenerated = "is_auto_generated"
        case triggerSource   = "trigger_source"
        case createdAt       = "created_at"
    }

    func toModel() -> FollowUp {
        let fu = FollowUp(
            id: id,
            companyId: companyId,
            opportunityId: opportunityId,
            title: title,
            type: FollowUpType(rawValue: type) ?? .custom,
            dueAt: SupabaseDate.parse(dueAt) ?? Date(),
            createdAt: SupabaseDate.parse(createdAt) ?? Date()
        )
        fu.clientId = clientId
        fu.descriptionText = description
        fu.status = FollowUpStatus(rawValue: status) ?? .pending
        fu.reminderAt = reminderAt.flatMap { SupabaseDate.parse($0) }
        fu.assignedTo = assignedTo
        fu.createdBy = createdBy
        fu.completedAt = completedAt.flatMap { SupabaseDate.parse($0) }
        fu.completionNotes = completionNotes
        fu.isAutoGenerated = isAutoGenerated ?? false
        fu.triggerSource = triggerSource
        return fu
    }
}

struct CreateFollowUpDTO: Codable {
    let companyId: String
    let opportunityId: String?
    let title: String                // REQUIRED — NOT NULL on DB, no backfill trigger
    let description: String?
    let type: String
    let dueAt: String
    let reminderAt: String?
    let assignedTo: String?

    enum CodingKeys: String, CodingKey {
        case companyId     = "company_id"
        case opportunityId = "opportunity_id"
        case title
        case description
        case type
        case dueAt         = "due_at"
        case reminderAt    = "reminder_at"
        case assignedTo    = "assigned_to"
    }
}

// MARK: - Stage Transition

struct StageTransitionDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let opportunityId: String
    let fromStage: String?
    let toStage: String
    let transitionedAt: String
    let transitionedBy: String?
    let durationInStage: String?     // Postgres `interval` arrives as ISO 8601 string

    enum CodingKeys: String, CodingKey {
        case id
        case companyId        = "company_id"
        case opportunityId    = "opportunity_id"
        case fromStage        = "from_stage"
        case toStage          = "to_stage"
        case transitionedAt   = "transitioned_at"
        case transitionedBy   = "transitioned_by"
        case durationInStage  = "duration_in_stage"
    }

    func toModel() -> StageTransition {
        StageTransition(
            id: id,
            companyId: companyId,
            opportunityId: opportunityId,
            fromStage: fromStage.flatMap { PipelineStage(rawValue: $0) },
            toStage: PipelineStage(rawValue: toStage) ?? .newLead,
            transitionedAt: SupabaseDate.parse(transitionedAt) ?? Date(),
            transitionedBy: transitionedBy,
            durationInStage: durationInStage.flatMap { ISO8601DurationParser.parse($0) }
        )
    }
}

// MARK: - ISO 8601 Duration Parser

/// Minimal parser for Postgres `interval` text format (e.g. "P0Y0M0DT2H30M0S" or "2 days 03:00:00").
/// Returns seconds as TimeInterval.
enum ISO8601DurationParser {
    static func parse(_ raw: String) -> TimeInterval? {
        // Postgres default format is "[N years] [N mons] [N days] HH:MM:SS"
        // ISO 8601 format is "PnYnMnDTnHnMnS"
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("P") {
            return parseISO8601(trimmed)
        }
        return parsePostgresInterval(trimmed)
    }

    private static func parseISO8601(_ s: String) -> TimeInterval? {
        // ISO8601DateFormatter doesn't parse durations directly — manual regex parse.
        var total: TimeInterval = 0
        let pattern = #"(\d+)([YMWDHS])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(s.startIndex..<s.endIndex, in: s)
        let tIndex = s.firstIndex(of: "T")
        regex.enumerateMatches(in: s, range: nsRange) { match, _, _ in
            guard let match = match,
                  let valRange = Range(match.range(at: 1), in: s),
                  let unitRange = Range(match.range(at: 2), in: s) else { return }
            guard let val = Double(s[valRange]) else { return }
            let unit = s[unitRange]
            // M is ambiguous: months (before T) vs minutes (after T).
            let isAfterT: Bool = {
                guard let tIndex else { return false }
                return unitRange.lowerBound > tIndex
            }()
            switch unit {
            case "Y": total += val * 365 * 86400
            case "M": total += isAfterT ? val * 60 : val * 30 * 86400
            case "W": total += val * 7 * 86400
            case "D": total += val * 86400
            case "H": total += val * 3600
            case "S": total += val
            default:  break
            }
        }
        return total > 0 ? total : nil
    }

    private static func parsePostgresInterval(_ s: String) -> TimeInterval? {
        // Examples: "2 days 03:00:00", "03:00:00", "1 year 2 mons 3 days 04:05:06"
        var total: TimeInterval = 0
        let parts = s.split(separator: " ")
        var i = 0
        while i < parts.count {
            let token = parts[i]
            if let val = Double(token), i + 1 < parts.count {
                let unit = parts[i + 1].lowercased()
                if unit.hasPrefix("year")  { total += val * 365 * 86400 }
                if unit.hasPrefix("mon")   { total += val * 30 * 86400 }
                if unit.hasPrefix("day")   { total += val * 86400 }
                if unit.hasPrefix("hour")  { total += val * 3600 }
                if unit.hasPrefix("min")   { total += val * 60 }
                if unit.hasPrefix("sec")   { total += val }
                i += 2
            } else if token.contains(":") {
                let timeParts = token.split(separator: ":")
                if timeParts.count == 3,
                   let h = Double(timeParts[0]),
                   let m = Double(timeParts[1]),
                   let sec = Double(timeParts[2]) {
                    total += h * 3600 + m * 60 + sec
                }
                i += 1
            } else {
                i += 1
            }
        }
        return total > 0 ? total : nil
    }
}
