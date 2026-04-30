//
//  OpportunityDTOs.swift
//  OPS
//
//  Data Transfer Objects for Pipeline/Opportunity Supabase tables.
//

import Foundation

struct OpportunityDTO: Codable, Identifiable {
    let id: String
    let companyId: String
    let contactName: String?
    let contactEmail: String?
    let contactPhone: String?
    let description: String?
    let estimatedValue: Double?
    let stage: String
    let source: String?
    let projectId: String?
    let clientId: String?
    let lostReason: String?
    let quoteDeliveryMethod: String?
    let createdAt: String
    let updatedAt: String
    let lastActivityAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId            = "company_id"
        case contactName          = "contact_name"
        case contactEmail         = "contact_email"
        case contactPhone         = "contact_phone"
        case description
        case estimatedValue       = "estimated_value"
        case stage
        case source
        case projectId            = "project_id"
        case clientId             = "client_id"
        case lostReason           = "lost_reason"
        case quoteDeliveryMethod  = "quote_delivery_method"
        case createdAt            = "created_at"
        case updatedAt            = "updated_at"
        case lastActivityAt       = "last_activity_at"
    }

    func toModel() -> Opportunity {
        let opp = Opportunity(
            id: id,
            companyId: companyId,
            contactName: contactName ?? "",
            stage: PipelineStage(rawValue: stage) ?? .newLead,
            createdAt: SupabaseDate.parse(createdAt) ?? Date(),
            updatedAt: SupabaseDate.parse(updatedAt) ?? Date()
        )
        opp.contactEmail = contactEmail
        opp.contactPhone = contactPhone
        opp.descriptionText = description
        opp.estimatedValue = estimatedValue
        opp.source = source
        opp.projectId = projectId
        opp.clientId = clientId
        opp.lostReason = lostReason
        if let method = quoteDeliveryMethod { opp.quoteDeliveryMethod = QuoteDeliveryMethod(rawValue: method) }
        if let la = lastActivityAt { opp.lastActivityAt = SupabaseDate.parse(la) }
        return opp
    }
}

struct CreateOpportunityDTO: Codable {
    let companyId: String
    let contactName: String
    let contactEmail: String?
    let contactPhone: String?
    let description: String?
    let estimatedValue: Double?
    let source: String?
    let quoteDeliveryMethod: String?
    /// Optional link to an existing Client row. Set this when the
    /// opportunity is being created alongside (or from) a known client —
    /// e.g. the auto-create-lead path triggered by ClientSheet (bug
    /// 321e65c8). When omitted, the opportunity is unlinked and can be
    /// associated later via UpdateOpportunityDTO.clientId.
    let clientId: String?

    init(
        companyId: String,
        contactName: String,
        contactEmail: String? = nil,
        contactPhone: String? = nil,
        description: String? = nil,
        estimatedValue: Double? = nil,
        source: String? = nil,
        quoteDeliveryMethod: String? = nil,
        clientId: String? = nil
    ) {
        self.companyId = companyId
        self.contactName = contactName
        self.contactEmail = contactEmail
        self.contactPhone = contactPhone
        self.description = description
        self.estimatedValue = estimatedValue
        self.source = source
        self.quoteDeliveryMethod = quoteDeliveryMethod
        self.clientId = clientId
    }

    enum CodingKeys: String, CodingKey {
        case companyId            = "company_id"
        case contactName          = "contact_name"
        case contactEmail         = "contact_email"
        case contactPhone         = "contact_phone"
        case description
        case estimatedValue       = "estimated_value"
        case source
        case quoteDeliveryMethod  = "quote_delivery_method"
        case clientId             = "client_id"
    }
}

struct UpdateOpportunityDTO: Codable {
    var contactName: String?
    var contactEmail: String?
    var contactPhone: String?
    var description: String?
    var estimatedValue: Double?
    var source: String?
    var clientId: String?
    var projectId: String?
    var quoteDeliveryMethod: String?

    enum CodingKeys: String, CodingKey {
        case contactName          = "contact_name"
        case contactEmail         = "contact_email"
        case contactPhone         = "contact_phone"
        case description
        case estimatedValue       = "estimated_value"
        case source
        case clientId             = "client_id"
        case projectId            = "project_id"
        case quoteDeliveryMethod  = "quote_delivery_method"
    }
}

struct ActivityDTO: Codable, Identifiable {
    let id: String
    let opportunityId: String
    let companyId: String
    let type: String
    let content: String?
    let createdBy: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case opportunityId = "opportunity_id"
        case companyId     = "company_id"
        case type
        case content
        case createdBy     = "created_by"
        case createdAt     = "created_at"
    }

    func toModel() -> Activity {
        let act = Activity(
            id: id,
            opportunityId: opportunityId,
            companyId: companyId,
            type: ActivityType(rawValue: type) ?? .note,
            createdAt: SupabaseDate.parse(createdAt) ?? Date()
        )
        act.body = content
        act.createdBy = createdBy
        return act
    }
}

struct CreateActivityDTO: Codable {
    let opportunityId: String
    let companyId: String
    let type: String
    let content: String?

    enum CodingKeys: String, CodingKey {
        case opportunityId = "opportunity_id"
        case companyId     = "company_id"
        case type
        case content
    }
}

struct FollowUpDTO: Codable, Identifiable {
    let id: String
    let opportunityId: String
    let companyId: String
    let type: String
    let status: String
    let dueAt: String
    let assignedTo: String?
    let notes: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case opportunityId = "opportunity_id"
        case companyId     = "company_id"
        case type
        case status
        case dueAt         = "due_at"
        case assignedTo    = "assigned_to"
        case notes
        case createdAt     = "created_at"
    }

    func toModel() -> FollowUp {
        let fu = FollowUp(
            id: id,
            opportunityId: opportunityId,
            companyId: companyId,
            type: FollowUpType(rawValue: type) ?? .custom,
            dueAt: SupabaseDate.parse(dueAt) ?? Date(),
            createdAt: SupabaseDate.parse(createdAt) ?? Date()
        )
        fu.status = FollowUpStatus(rawValue: status) ?? .pending
        fu.assignedTo = assignedTo
        fu.notes = notes
        return fu
    }
}

struct CreateFollowUpDTO: Codable {
    let opportunityId: String
    let companyId: String
    let type: String
    let dueAt: String
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case opportunityId = "opportunity_id"
        case companyId     = "company_id"
        case type
        case dueAt         = "due_at"
        case notes
    }
}
