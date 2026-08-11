//
//  SiteVisitDTOs.swift
//  OPS
//
//  Explicit Supabase wire contracts for durable, cross-device site visits.
//  The SwiftData models are never encoded directly: local-only search state,
//  retry flags, and file URLs must not leak into customer cloud rows.
//

import Foundation
import Supabase

enum SiteVisitPayloadError: Error, Equatable {
    case missingRequiredField(String)
    case invalidUUID(field: String, value: String)
    case unsupportedUpdateField(String)
    case invalidDimensions
}

// MARK: - Parent read DTO

struct SiteVisitDTO: Decodable, Equatable, Identifiable {
    let id: String
    let companyId: String
    let opportunityId: String?
    let projectId: String?
    let projectRef: String?
    let clientId: String?
    let clientRef: String?
    let scheduledAt: Date
    let durationMinutes: Int
    let assigneeIds: [String]
    let status: SiteVisitStatus
    let completedAt: Date?
    let notes: String?
    let internalNotes: String?
    let measurements: String?
    let photos: [String]
    let activityId: String?
    let calendarEventId: String?
    let bookedAt: Date?
    let reminderLeadMinutes: Int?
    let createdBy: String
    let createdAt: Date?
    let updatedAt: Date?
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId = "company_id"
        case opportunityId = "opportunity_id"
        case projectId = "project_id"
        case projectRef = "project_ref"
        case clientId = "client_id"
        case clientRef = "client_ref"
        case scheduledAt = "scheduled_at"
        case durationMinutes = "duration_minutes"
        case assigneeIds = "assignee_ids"
        case status
        case completedAt = "completed_at"
        case notes
        case internalNotes = "internal_notes"
        case measurements
        case photos
        case activityId = "activity_id"
        case calendarEventId = "calendar_event_id"
        case bookedAt = "booked_at"
        case reminderLeadMinutes = "reminder_lead_minutes"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try SiteVisitWire.requiredUUID(try c.decode(String.self, forKey: .id), key: CodingKeys.id)
        companyId = try SiteVisitWire.requiredText(try c.decode(String.self, forKey: .companyId), key: CodingKeys.companyId).lowercased()
        opportunityId = try SiteVisitWire.optionalUUID(try c.decodeIfPresent(String.self, forKey: .opportunityId), key: CodingKeys.opportunityId)
        projectId = try c.decodeIfPresent(String.self, forKey: .projectId)?.lowercased()
        projectRef = try SiteVisitWire.optionalUUID(try c.decodeIfPresent(String.self, forKey: .projectRef), key: CodingKeys.projectRef)
        clientId = try c.decodeIfPresent(String.self, forKey: .clientId)?.lowercased()
        clientRef = try SiteVisitWire.optionalUUID(try c.decodeIfPresent(String.self, forKey: .clientRef), key: CodingKeys.clientRef)
        scheduledAt = try SiteVisitWire.requiredDate(c, key: .scheduledAt)
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 60
        let rawAssignees = try c.decodeIfPresent([String].self, forKey: .assigneeIds) ?? []
        assigneeIds = try rawAssignees.enumerated().map { index, raw in
            try SiteVisitWire.requiredUUID(raw, field: "assignee_ids[\(index)]", codingPath: c.codingPath)
        }
        status = try c.decode(SiteVisitStatus.self, forKey: .status)
        completedAt = try SiteVisitWire.optionalDate(c, key: .completedAt)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        internalNotes = try c.decodeIfPresent(String.self, forKey: .internalNotes)
        measurements = try c.decodeIfPresent(String.self, forKey: .measurements)
        photos = try c.decodeIfPresent([String].self, forKey: .photos) ?? []
        activityId = try SiteVisitWire.optionalUUID(try c.decodeIfPresent(String.self, forKey: .activityId), key: CodingKeys.activityId)
        calendarEventId = try c.decodeIfPresent(String.self, forKey: .calendarEventId)?.lowercased()
        bookedAt = try SiteVisitWire.optionalDate(c, key: .bookedAt)
        reminderLeadMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderLeadMinutes)
        createdBy = try SiteVisitWire.requiredText(try c.decode(String.self, forKey: .createdBy), key: CodingKeys.createdBy).lowercased()
        createdAt = try SiteVisitWire.optionalDate(c, key: .createdAt)
        updatedAt = try SiteVisitWire.optionalDate(c, key: .updatedAt)
        deletedAt = try SiteVisitWire.optionalDate(c, key: .deletedAt)
    }

    func replacing(
        notes: String? = nil,
        internalNotes: String? = nil,
        activityId: String? = nil,
        deletedAt: Date? = nil
    ) -> SiteVisitDTO {
        SiteVisitDTO(
            id: id,
            companyId: companyId,
            opportunityId: opportunityId,
            projectId: projectId,
            projectRef: projectRef,
            clientId: clientId,
            clientRef: clientRef,
            scheduledAt: scheduledAt,
            durationMinutes: durationMinutes,
            assigneeIds: assigneeIds,
            status: status,
            completedAt: completedAt,
            notes: notes ?? self.notes,
            internalNotes: internalNotes ?? self.internalNotes,
            measurements: measurements,
            photos: photos,
            activityId: activityId ?? self.activityId,
            calendarEventId: calendarEventId,
            bookedAt: bookedAt,
            reminderLeadMinutes: reminderLeadMinutes,
            createdBy: createdBy,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt ?? self.deletedAt
        )
    }

    private init(
        id: String,
        companyId: String,
        opportunityId: String?,
        projectId: String?,
        projectRef: String?,
        clientId: String?,
        clientRef: String?,
        scheduledAt: Date,
        durationMinutes: Int,
        assigneeIds: [String],
        status: SiteVisitStatus,
        completedAt: Date?,
        notes: String?,
        internalNotes: String?,
        measurements: String?,
        photos: [String],
        activityId: String?,
        calendarEventId: String?,
        bookedAt: Date?,
        reminderLeadMinutes: Int?,
        createdBy: String,
        createdAt: Date?,
        updatedAt: Date?,
        deletedAt: Date?
    ) {
        self.id = id
        self.companyId = companyId
        self.opportunityId = opportunityId
        self.projectId = projectId
        self.projectRef = projectRef
        self.clientId = clientId
        self.clientRef = clientRef
        self.scheduledAt = scheduledAt
        self.durationMinutes = durationMinutes
        self.assigneeIds = assigneeIds
        self.status = status
        self.completedAt = completedAt
        self.notes = notes
        self.internalNotes = internalNotes
        self.measurements = measurements
        self.photos = photos
        self.activityId = activityId
        self.calendarEventId = calendarEventId
        self.bookedAt = bookedAt
        self.reminderLeadMinutes = reminderLeadMinutes
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

// MARK: - Child read DTOs

struct SiteVisitArtifactDTO: Decodable, Equatable, Identifiable {
    let id: String
    let siteVisitId: String
    let companyId: String
    let opportunityId: String?
    let kind: SiteVisitCaptureArtifactKind
    let source: SiteVisitCaptureSource
    let title: String?
    let body: String?
    let assetURL: String?
    let renderedAssetURL: String?
    let thumbnailURL: String?
    let dimensions: DimensionsData?
    let deckDesignId: String?
    let includedInProjectReview: Bool
    let capturedAt: Date
    let createdBy: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case siteVisitId = "site_visit_id"
        case companyId = "company_id"
        case opportunityId = "opportunity_id"
        case kind, source, title, body
        case assetURL = "asset_url"
        case renderedAssetURL = "rendered_asset_url"
        case thumbnailURL = "thumbnail_url"
        case dimensions
        case deckDesignId = "deck_design_id"
        case includedInProjectReview = "included_in_project_review"
        case capturedAt = "captured_at"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try SiteVisitWire.requiredUUID(try c.decode(String.self, forKey: .id), key: CodingKeys.id)
        siteVisitId = try SiteVisitWire.requiredUUID(try c.decode(String.self, forKey: .siteVisitId), key: CodingKeys.siteVisitId)
        companyId = try SiteVisitWire.requiredText(try c.decode(String.self, forKey: .companyId), key: CodingKeys.companyId).lowercased()
        opportunityId = try SiteVisitWire.optionalUUID(try c.decodeIfPresent(String.self, forKey: .opportunityId), key: CodingKeys.opportunityId)
        kind = try c.decode(SiteVisitCaptureArtifactKind.self, forKey: .kind)
        source = try c.decode(SiteVisitCaptureSource.self, forKey: .source)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        assetURL = try c.decodeIfPresent(String.self, forKey: .assetURL)
        renderedAssetURL = try c.decodeIfPresent(String.self, forKey: .renderedAssetURL)
        thumbnailURL = try c.decodeIfPresent(String.self, forKey: .thumbnailURL)
        dimensions = try SiteVisitWire.dimensions(c, key: .dimensions)
        deckDesignId = try SiteVisitWire.optionalUUID(try c.decodeIfPresent(String.self, forKey: .deckDesignId), key: CodingKeys.deckDesignId)
        includedInProjectReview = try c.decodeIfPresent(Bool.self, forKey: .includedInProjectReview) ?? true
        capturedAt = try SiteVisitWire.requiredDate(c, key: .capturedAt)
        createdBy = try SiteVisitWire.requiredText(try c.decode(String.self, forKey: .createdBy), key: CodingKeys.createdBy).lowercased()
        createdAt = try SiteVisitWire.requiredDate(c, key: .createdAt)
        updatedAt = try SiteVisitWire.requiredDate(c, key: .updatedAt)
        deletedAt = try SiteVisitWire.optionalDate(c, key: .deletedAt)
    }
}

struct SiteVisitChecklistAnswerDTO: Decodable, Equatable, Identifiable {
    let id: String
    let siteVisitId: String
    let companyId: String
    let opportunityId: String?
    let siteVisitTypeId: String?
    let fieldId: String
    let label: String
    let kind: SiteVisitFieldKind
    let required: Bool
    let helpText: String?
    let sortOrder: Int
    let answerValue: SiteVisitChecklistValue
    let createdBy: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case siteVisitId = "site_visit_id"
        case companyId = "company_id"
        case opportunityId = "opportunity_id"
        case siteVisitTypeId = "site_visit_type_id"
        case fieldId = "field_id"
        case label, kind, required
        case helpText = "help_text"
        case sortOrder = "sort_order"
        case answerValue = "answer_value"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try SiteVisitWire.requiredUUID(try c.decode(String.self, forKey: .id), key: CodingKeys.id)
        siteVisitId = try SiteVisitWire.requiredUUID(try c.decode(String.self, forKey: .siteVisitId), key: CodingKeys.siteVisitId)
        companyId = try SiteVisitWire.requiredText(try c.decode(String.self, forKey: .companyId), key: CodingKeys.companyId).lowercased()
        opportunityId = try SiteVisitWire.optionalUUID(try c.decodeIfPresent(String.self, forKey: .opportunityId), key: CodingKeys.opportunityId)
        siteVisitTypeId = try c.decodeIfPresent(String.self, forKey: .siteVisitTypeId)
        fieldId = try SiteVisitWire.requiredText(try c.decode(String.self, forKey: .fieldId), key: CodingKeys.fieldId)
        label = try SiteVisitWire.requiredText(try c.decode(String.self, forKey: .label), key: CodingKeys.label)
        kind = try c.decode(SiteVisitFieldKind.self, forKey: .kind)
        required = try c.decodeIfPresent(Bool.self, forKey: .required) ?? false
        helpText = try c.decodeIfPresent(String.self, forKey: .helpText)
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        answerValue = SiteVisitWire.canonicalChecklistValue(
            try c.decodeIfPresent(SiteVisitChecklistValue.self, forKey: .answerValue) ?? .empty
        )
        createdBy = try SiteVisitWire.requiredText(try c.decode(String.self, forKey: .createdBy), key: CodingKeys.createdBy).lowercased()
        createdAt = try SiteVisitWire.requiredDate(c, key: .createdAt)
        updatedAt = try SiteVisitWire.requiredDate(c, key: .updatedAt)
        deletedAt = try SiteVisitWire.optionalDate(c, key: .deletedAt)
    }
}

struct SiteVisitIdentityDraftDTO: Decodable, Equatable, Identifiable {
    let id: String
    let siteVisitId: String
    let companyId: String
    let opportunityId: String?
    let clientId: String?
    let subClientId: String?
    let clientName: String
    let contactName: String
    let preferredEmail: String
    let additionalEmails: [String]
    let phoneNumber: String
    let address: String
    let notes: String
    let createdBy: String
    let lastCommittedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case siteVisitId = "site_visit_id"
        case companyId = "company_id"
        case opportunityId = "opportunity_id"
        case clientId = "client_id"
        case subClientId = "sub_client_id"
        case clientName = "client_name"
        case contactName = "contact_name"
        case preferredEmail = "preferred_email"
        case additionalEmails = "additional_emails"
        case phoneNumber = "phone_number"
        case address, notes
        case createdBy = "created_by"
        case lastCommittedAt = "last_committed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try SiteVisitWire.requiredUUID(try c.decode(String.self, forKey: .id), key: CodingKeys.id)
        siteVisitId = try SiteVisitWire.requiredUUID(try c.decode(String.self, forKey: .siteVisitId), key: CodingKeys.siteVisitId)
        companyId = try SiteVisitWire.requiredText(try c.decode(String.self, forKey: .companyId), key: CodingKeys.companyId).lowercased()
        opportunityId = try SiteVisitWire.optionalUUID(try c.decodeIfPresent(String.self, forKey: .opportunityId), key: CodingKeys.opportunityId)
        clientId = try SiteVisitWire.optionalUUID(try c.decodeIfPresent(String.self, forKey: .clientId), key: CodingKeys.clientId)
        subClientId = try SiteVisitWire.optionalUUID(try c.decodeIfPresent(String.self, forKey: .subClientId), key: CodingKeys.subClientId)
        clientName = try c.decodeIfPresent(String.self, forKey: .clientName) ?? ""
        contactName = try c.decodeIfPresent(String.self, forKey: .contactName) ?? ""
        preferredEmail = try c.decodeIfPresent(String.self, forKey: .preferredEmail) ?? ""
        additionalEmails = try c.decodeIfPresent([String].self, forKey: .additionalEmails) ?? []
        phoneNumber = try c.decodeIfPresent(String.self, forKey: .phoneNumber) ?? ""
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        createdBy = try SiteVisitWire.requiredText(try c.decode(String.self, forKey: .createdBy), key: CodingKeys.createdBy).lowercased()
        lastCommittedAt = try SiteVisitWire.optionalDate(c, key: .lastCommittedAt)
        createdAt = try SiteVisitWire.requiredDate(c, key: .createdAt)
        updatedAt = try SiteVisitWire.requiredDate(c, key: .updatedAt)
        deletedAt = try SiteVisitWire.optionalDate(c, key: .deletedAt)
    }
}

// MARK: - Explicit write payloads

struct CreateSiteVisitDTO: Codable, Equatable {
    let id: String
    let companyId: String
    let opportunityId: String?
    let projectId: String?
    let projectRef: String?
    let clientId: String?
    let clientRef: String?
    let scheduledAt: String
    let durationMinutes: Int
    let assigneeIds: [String]
    let status: SiteVisitStatus
    let completedAt: String?
    let notes: String?
    let internalNotes: String?
    let measurements: String?
    let photos: [String]
    let activityId: String?
    let calendarEventId: String?
    let createdBy: String
    let createdAt: String
    let updatedAt: String?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case companyId = "company_id"
        case opportunityId = "opportunity_id"
        case projectId = "project_id"
        case projectRef = "project_ref"
        case clientId = "client_id"
        case clientRef = "client_ref"
        case scheduledAt = "scheduled_at"
        case durationMinutes = "duration_minutes"
        case assigneeIds = "assignee_ids"
        case status
        case completedAt = "completed_at"
        case notes
        case internalNotes = "internal_notes"
        case measurements, photos
        case activityId = "activity_id"
        case calendarEventId = "calendar_event_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(model: SiteVisit) throws {
        guard let scheduledAt = model.scheduledAt else {
            throw SiteVisitPayloadError.missingRequiredField("scheduled_at")
        }
        guard let createdBy = model.createdBy, !createdBy.isEmpty else {
            throw SiteVisitPayloadError.missingRequiredField("created_by")
        }
        id = try SiteVisitWire.payloadUUID(model.id, field: "id")
        companyId = try SiteVisitWire.payloadText(model.companyId, field: "company_id").lowercased()
        opportunityId = try SiteVisitWire.payloadOptionalUUID(model.opportunityId, field: "opportunity_id")
        projectId = model.projectId?.lowercased()
        projectRef = try SiteVisitWire.payloadOptionalUUID(model.projectRef, field: "project_ref")
        clientId = model.clientId?.lowercased()
        clientRef = try SiteVisitWire.payloadOptionalUUID(model.clientRef, field: "client_ref")
        self.scheduledAt = SupabaseDate.format(scheduledAt)
        durationMinutes = model.durationMinutes
        assigneeIds = try model.assigneeIds.map { try SiteVisitWire.payloadUUID($0, field: "assignee_ids") }
        status = model.status
        completedAt = model.completedAt.map(SupabaseDate.format)
        notes = model.notes
        internalNotes = model.internalNotes
        measurements = model.measurements
        photos = model.photos
        activityId = try SiteVisitWire.payloadOptionalUUID(model.loggedActivityId, field: "activity_id")
        calendarEventId = model.calendarEventId?.lowercased()
        self.createdBy = createdBy.lowercased()
        createdAt = SupabaseDate.format(model.createdAt)
        updatedAt = model.updatedAt.map(SupabaseDate.format)
        deletedAt = model.deletedAt.map(SupabaseDate.format)
    }
}

struct SiteVisitUpdateDTO: Codable, Equatable {
    let values: [String: AnyJSON]

    private static let allowedFields: Set<String> = [
        "opportunity_id", "project_id", "project_ref", "client_id", "client_ref",
        "scheduled_at", "duration_minutes", "assignee_ids", "status", "completed_at",
        "notes", "internal_notes", "measurements", "photos", "activity_id",
        "calendar_event_id", "deleted_at",
    ]

    init(values: [String: AnyJSON]) throws {
        if let unsupported = values.keys.first(where: { !Self.allowedFields.contains($0) }) {
            throw SiteVisitPayloadError.unsupportedUpdateField(unsupported)
        }
        self.values = values
    }

    init(from decoder: Decoder) throws {
        values = try [String: AnyJSON](from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try values.encode(to: encoder)
    }
}

struct UpsertSiteVisitArtifactDTO: Codable, Equatable {
    let id: String
    let siteVisitId: String
    let companyId: String
    let opportunityId: String?
    let kind: SiteVisitCaptureArtifactKind
    let source: SiteVisitCaptureSource
    let title: String?
    let body: String?
    let assetURL: String?
    let renderedAssetURL: String?
    let thumbnailURL: String?
    let dimensions: AnyJSON?
    let deckDesignId: String?
    let includedInProjectReview: Bool
    let capturedAt: String
    let createdBy: String
    let createdAt: String
    let updatedAt: String?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case siteVisitId = "site_visit_id"
        case companyId = "company_id"
        case opportunityId = "opportunity_id"
        case kind, source, title, body
        case assetURL = "asset_url"
        case renderedAssetURL = "rendered_asset_url"
        case thumbnailURL = "thumbnail_url"
        case dimensions
        case deckDesignId = "deck_design_id"
        case includedInProjectReview = "included_in_project_review"
        case capturedAt = "captured_at"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(model: SiteVisitCaptureArtifact) throws {
        guard let createdBy = model.createdBy, !createdBy.isEmpty else {
            throw SiteVisitPayloadError.missingRequiredField("created_by")
        }
        id = try SiteVisitWire.payloadUUID(model.id, field: "id")
        siteVisitId = try SiteVisitWire.payloadUUID(model.siteVisitId, field: "site_visit_id")
        companyId = try SiteVisitWire.payloadText(model.companyId, field: "company_id").lowercased()
        opportunityId = try SiteVisitWire.payloadOptionalUUID(model.opportunityId, field: "opportunity_id")
        kind = model.kind
        source = model.source
        title = model.title
        body = model.body
        // Device-local/file URLs are never valid server metadata. The durable
        // media operation uploads them first, then queues a second artifact
        // upsert containing only its deterministic public URLs.
        assetURL = SiteVisitWire.remoteAssetURL(model.localAssetURL)
        renderedAssetURL = SiteVisitWire.remoteAssetURL(model.renderedAssetURL)
        thumbnailURL = SiteVisitWire.remoteAssetURL(model.thumbnailURL)
        dimensions = try model.dimensionsJSON.flatMap(SiteVisitWire.anyJSONDimensions)
        deckDesignId = try SiteVisitWire.payloadOptionalUUID(model.deckDesignId, field: "deck_design_id")
        includedInProjectReview = model.includedInProjectReview
        capturedAt = SupabaseDate.format(model.capturedAt)
        self.createdBy = createdBy.lowercased()
        createdAt = SupabaseDate.format(model.createdAt)
        updatedAt = model.updatedAt.map(SupabaseDate.format)
        deletedAt = model.deletedAt.map(SupabaseDate.format)
    }
}

struct UpsertSiteVisitChecklistAnswerDTO: Codable, Equatable {
    let id: String
    let siteVisitId: String
    let companyId: String
    let opportunityId: String?
    let siteVisitTypeId: String?
    let fieldId: String
    let label: String
    let kind: SiteVisitFieldKind
    let required: Bool
    let helpText: String?
    let sortOrder: Int
    let answerValue: SiteVisitChecklistValue
    let createdBy: String
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case siteVisitId = "site_visit_id"
        case companyId = "company_id"
        case opportunityId = "opportunity_id"
        case siteVisitTypeId = "site_visit_type_id"
        case fieldId = "field_id"
        case label, kind, required
        case helpText = "help_text"
        case sortOrder = "sort_order"
        case answerValue = "answer_value"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(model: SiteVisitChecklistAnswer) throws {
        guard let createdBy = model.createdBy, !createdBy.isEmpty else {
            throw SiteVisitPayloadError.missingRequiredField("created_by")
        }
        id = try SiteVisitWire.payloadUUID(model.id, field: "id")
        siteVisitId = try SiteVisitWire.payloadUUID(model.siteVisitId, field: "site_visit_id")
        companyId = try SiteVisitWire.payloadText(model.companyId, field: "company_id").lowercased()
        opportunityId = try SiteVisitWire.payloadOptionalUUID(model.opportunityId, field: "opportunity_id")
        siteVisitTypeId = model.siteVisitTypeId
        fieldId = try SiteVisitWire.payloadText(model.fieldId, field: "field_id")
        label = try SiteVisitWire.payloadText(model.label, field: "label")
        kind = model.kind
        required = model.required
        helpText = model.helpText
        sortOrder = model.sortOrder
        answerValue = SiteVisitWire.canonicalChecklistValue(model.answerValue)
        self.createdBy = createdBy.lowercased()
        createdAt = SupabaseDate.format(model.createdAt)
        updatedAt = SupabaseDate.format(model.updatedAt ?? model.createdAt)
        deletedAt = model.deletedAt.map(SupabaseDate.format)
    }
}

struct UpsertSiteVisitIdentityDraftDTO: Codable, Equatable {
    let id: String
    let siteVisitId: String
    let companyId: String
    let opportunityId: String?
    let clientId: String?
    let subClientId: String?
    let clientName: String
    let contactName: String
    let preferredEmail: String
    let additionalEmails: [String]
    let phoneNumber: String
    let address: String
    let notes: String
    let createdBy: String
    let lastCommittedAt: String?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case siteVisitId = "site_visit_id"
        case companyId = "company_id"
        case opportunityId = "opportunity_id"
        case clientId = "client_id"
        case subClientId = "sub_client_id"
        case clientName = "client_name"
        case contactName = "contact_name"
        case preferredEmail = "preferred_email"
        case additionalEmails = "additional_emails"
        case phoneNumber = "phone_number"
        case address, notes
        case createdBy = "created_by"
        case lastCommittedAt = "last_committed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(model: SiteVisitIdentityDraft) throws {
        guard let createdBy = model.createdBy, !createdBy.isEmpty else {
            throw SiteVisitPayloadError.missingRequiredField("created_by")
        }
        id = try SiteVisitWire.payloadUUID(model.id, field: "id")
        siteVisitId = try SiteVisitWire.payloadUUID(model.siteVisitId, field: "site_visit_id")
        companyId = try SiteVisitWire.payloadText(model.companyId, field: "company_id").lowercased()
        opportunityId = try SiteVisitWire.payloadOptionalUUID(model.opportunityId, field: "opportunity_id")
        clientId = try SiteVisitWire.payloadOptionalUUID(model.clientId, field: "client_id")
        subClientId = try SiteVisitWire.payloadOptionalUUID(model.subClientId, field: "sub_client_id")
        clientName = model.clientName
        contactName = model.contactName
        preferredEmail = model.preferredEmail
        additionalEmails = model.additionalEmails
        phoneNumber = model.phoneNumber
        address = model.address
        notes = model.notes
        self.createdBy = createdBy.lowercased()
        lastCommittedAt = model.lastCommittedAt.map(SupabaseDate.format)
        createdAt = SupabaseDate.format(model.createdAt)
        updatedAt = SupabaseDate.format(model.updatedAt)
        deletedAt = model.deletedAt.map(SupabaseDate.format)
    }
}

struct SiteVisitCompletionPayload: Codable, Equatable {
    let notes: String?
    let measurements: String?
    let photos: [String]?
    let internalNotes: String?

    enum CodingKeys: String, CodingKey {
        case notes, measurements, photos
        case internalNotes = "internal_notes"
    }

    init(
        notes: String? = nil,
        measurements: String? = nil,
        photos: [String]? = nil,
        internalNotes: String? = nil
    ) {
        self.notes = notes
        self.measurements = measurements
        self.photos = photos
        self.internalNotes = internalNotes
    }
}

struct CompleteSiteVisitRPCParams: Codable, Equatable {
    let p_site_visit_id: String
    let p_completion: SiteVisitCompletionPayload
}

struct SiteVisitCompletionResponseDTO: Decodable, Equatable {
    let visit: SiteVisitDTO
    let activityId: String?

    enum CodingKeys: String, CodingKey {
        case visit
        case activityId = "activity_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        visit = try c.decode(SiteVisitDTO.self, forKey: .visit)
        activityId = try SiteVisitWire.optionalUUID(try c.decodeIfPresent(String.self, forKey: .activityId), key: CodingKeys.activityId)
    }
}

// MARK: - Bundles

struct SiteVisitDeltaBundleDTO: Equatable {
    let visits: [SiteVisitDTO]
    let artifacts: [SiteVisitArtifactDTO]
    let checklistAnswers: [SiteVisitChecklistAnswerDTO]
    let identityDrafts: [SiteVisitIdentityDraftDTO]
}

struct SiteVisitBundleDTO: Decodable, Equatable {
    let visit: SiteVisitDTO
    let artifacts: [SiteVisitArtifactDTO]
    let checklistAnswers: [SiteVisitChecklistAnswerDTO]
    let identityDrafts: [SiteVisitIdentityDraftDTO]

    enum CodingKeys: String, CodingKey {
        case visit, artifacts
        case checklistAnswers = "checklist_answers"
        case identityDrafts = "identity_drafts"
    }
}

// Immutable value payloads cross from the MainActor realtime decoder into the
// background SwiftData actor. Their stored members are value types; unchecked
// conformance avoids requiring every legacy enum nested inside DimensionsData
// to be retrofitted solely for this boundary.
extension SiteVisitDTO: @unchecked Sendable {}
extension SiteVisitArtifactDTO: @unchecked Sendable {}
extension SiteVisitChecklistAnswerDTO: @unchecked Sendable {}
extension SiteVisitIdentityDraftDTO: @unchecked Sendable {}
extension SiteVisitDeltaBundleDTO: @unchecked Sendable {}
extension SiteVisitBundleDTO: @unchecked Sendable {}

// MARK: - Strict wire helpers

private enum SiteVisitWire {
    static func remoteAssetURL(_ raw: String?) -> String? {
        guard let raw,
              let scheme = URLComponents(string: raw)?.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        return raw
    }

    static func requiredText<K: CodingKey>(_ raw: String, key: K) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [key], debugDescription: "\(key.stringValue) must not be empty")
            )
        }
        return trimmed
    }

    static func requiredUUID<K: CodingKey>(_ raw: String, key: K) throws -> String {
        try requiredUUID(raw, field: key.stringValue, codingPath: [key])
    }

    static func requiredUUID(_ raw: String, field: String, codingPath: [CodingKey]) throws -> String {
        guard let uuid = UUID(uuidString: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: codingPath, debugDescription: "\(field) must be a UUID")
            )
        }
        return uuid.uuidString.lowercased()
    }

    static func optionalUUID<K: CodingKey>(_ raw: String?, key: K) throws -> String? {
        guard let raw else { return nil }
        return try requiredUUID(raw, key: key)
    }

    static func requiredDate<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        key: K
    ) throws -> Date {
        let raw = try container.decode(String.self, forKey: key)
        guard let date = SupabaseDate.parse(raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "\(key.stringValue) is not a Supabase timestamp"
            )
        }
        return date
    }

    static func optionalDate<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        key: K
    ) throws -> Date? {
        guard let raw = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        guard let date = SupabaseDate.parse(raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "\(key.stringValue) is not a Supabase timestamp"
            )
        }
        return date
    }

    static func dimensions<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        key: K
    ) throws -> DimensionsData? {
        guard let value = try container.decodeIfPresent(AnyJSON.self, forKey: key) else {
            return nil
        }
        let data = try JSONEncoder().encode(value)
        do {
            return try DimensionsData.jsonDecoder.decode(DimensionsData.self, from: data)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "dimensions does not match DimensionsData: \(error)"
            )
        }
    }

    static func canonicalChecklistValue(_ value: SiteVisitChecklistValue) -> SiteVisitChecklistValue {
        SiteVisitChecklistValue(
            text: value.text,
            boolValue: value.boolValue,
            choice: value.choice,
            artifactIds: value.artifactIds.map { $0.lowercased() },
            deckDesignId: value.deckDesignId?.lowercased()
        )
    }

    static func payloadText(_ raw: String, field: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SiteVisitPayloadError.missingRequiredField(field)
        }
        return trimmed
    }

    static func payloadUUID(_ raw: String, field: String) throws -> String {
        guard let uuid = UUID(uuidString: raw) else {
            throw SiteVisitPayloadError.invalidUUID(field: field, value: raw)
        }
        return uuid.uuidString.lowercased()
    }

    static func payloadOptionalUUID(_ raw: String?, field: String) throws -> String? {
        guard let raw else { return nil }
        return try payloadUUID(raw, field: field)
    }

    static func anyJSONDimensions(_ json: String) throws -> AnyJSON {
        guard let data = json.data(using: .utf8) else {
            throw SiteVisitPayloadError.invalidDimensions
        }
        do {
            let dimensions = try DimensionsData.jsonDecoder.decode(DimensionsData.self, from: data)
            let normalized = try DimensionsData.jsonEncoder.encode(dimensions)
            return try JSONDecoder().decode(AnyJSON.self, from: normalized)
        } catch {
            throw SiteVisitPayloadError.invalidDimensions
        }
    }
}
