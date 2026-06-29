//
//  SiteVisitType.swift
//  OPS
//
//  Company-scoped site visit templates and per-visit checklist answer snapshots.
//

import Foundation
import SwiftData

enum SiteVisitFieldKind: String, Codable, CaseIterable, Hashable {
    case checkbox = "checkbox"
    case yesNoNA = "yes_no_na"
    case shortText = "short_text"
    case longText = "long_text"
    case measurement = "measurement"
    case photo = "photo"
    case photoMarkup = "photo_markup"
    case deckDesign = "deck_design"

    var displayName: String {
        switch self {
        case .checkbox: return "CHECK"
        case .yesNoNA: return "YES / NO / N/A"
        case .shortText: return "SHORT"
        case .longText: return "NOTES"
        case .measurement: return "MEASURE"
        case .photo: return "PHOTO"
        case .photoMarkup: return "PHOTO + MARKUP"
        case .deckDesign: return "DECK"
        }
    }
}

struct SiteVisitTypeFieldDefinition: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var kind: SiteVisitFieldKind
    var required: Bool
    var helpText: String?
    var sortOrder: Int

    init(
        id: String = UUID().uuidString,
        label: String,
        kind: SiteVisitFieldKind,
        required: Bool = false,
        helpText: String? = nil,
        sortOrder: Int
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.required = required
        self.helpText = helpText
        self.sortOrder = sortOrder
    }
}

struct SiteVisitChecklistValue: Codable, Equatable {
    var text: String?
    var boolValue: Bool?
    var choice: String?
    var artifactIds: [String]
    var deckDesignId: String?

    static let empty = SiteVisitChecklistValue()

    init(
        text: String? = nil,
        boolValue: Bool? = nil,
        choice: String? = nil,
        artifactIds: [String] = [],
        deckDesignId: String? = nil
    ) {
        self.text = text
        self.boolValue = boolValue
        self.choice = choice
        self.artifactIds = artifactIds
        self.deckDesignId = deckDesignId
    }

    static func text(_ value: String) -> SiteVisitChecklistValue {
        SiteVisitChecklistValue(text: value)
    }

    static func bool(_ value: Bool) -> SiteVisitChecklistValue {
        SiteVisitChecklistValue(boolValue: value)
    }

    static func choice(_ value: String) -> SiteVisitChecklistValue {
        SiteVisitChecklistValue(choice: value)
    }

    static func artifacts(_ ids: [String]) -> SiteVisitChecklistValue {
        SiteVisitChecklistValue(artifactIds: ids)
    }

    static func deckDesign(_ id: String) -> SiteVisitChecklistValue {
        SiteVisitChecklistValue(deckDesignId: id)
    }

    var isAnswered: Bool {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if boolValue != nil { return true }
        if let choice, !choice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !artifactIds.isEmpty { return true }
        if let deckDesignId, !deckDesignId.isEmpty { return true }
        return false
    }
}

@Model
final class SiteVisitType: Identifiable {
    @Attribute(.unique) var id: String
    var companyId: String
    var slug: String
    var name: String
    var descriptionText: String?
    var isSystemTemplate: Bool
    var isDefault: Bool
    var sortOrder: Int
    var fieldsData: Data?
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?
    var needsSync: Bool
    var lastSyncedAt: Date?

    init(
        id: String = UUID().uuidString,
        companyId: String,
        slug: String,
        name: String,
        descriptionText: String? = nil,
        isSystemTemplate: Bool = false,
        isDefault: Bool = false,
        sortOrder: Int = 0,
        fields: [SiteVisitTypeFieldDefinition] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.companyId = companyId
        self.slug = slug
        self.name = name
        self.descriptionText = descriptionText
        self.isSystemTemplate = isSystemTemplate
        self.isDefault = isDefault
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.needsSync = !isSystemTemplate
        self.fields = fields
    }

    var fields: [SiteVisitTypeFieldDefinition] {
        get {
            guard let fieldsData,
                  let decoded = try? JSONDecoder().decode(
                    [SiteVisitTypeFieldDefinition].self,
                    from: fieldsData
                  ) else { return [] }
            return decoded.sorted { $0.sortOrder < $1.sortOrder }
        }
        set {
            fieldsData = try? JSONEncoder().encode(newValue.sorted { $0.sortOrder < $1.sortOrder })
            updatedAt = Date()
            if !isSystemTemplate {
                needsSync = true
            }
        }
    }

    static func builtInTemplates(
        companyId: String,
        deckBuilderEnabled: Bool
    ) -> [SiteVisitType] {
        var deckFields: [SiteVisitTypeFieldDefinition] = [
            .init(id: "client-goals", label: "Client goals", kind: .longText, sortOrder: 10),
            .init(id: "existing-structure", label: "Existing structure", kind: .photoMarkup, sortOrder: 20),
            .init(id: "field-measurements", label: "Field measurements", kind: .measurement, required: true, sortOrder: 30),
        ]
        if deckBuilderEnabled {
            deckFields.append(
                .init(id: "deck-design", label: "Deck design", kind: .deckDesign, required: true, sortOrder: 40)
            )
        }

        return [
            SiteVisitType(
                id: "system-\(companyId)-generic-site-visit",
                companyId: companyId,
                slug: "generic_site_visit",
                name: "Generic Site Visit",
                descriptionText: "Base scope visit.",
                isSystemTemplate: true,
                isDefault: true,
                sortOrder: 0,
                fields: [
                    .init(id: "scope-notes", label: "Scope notes", kind: .longText, sortOrder: 10),
                    .init(id: "site-photos", label: "Site photos", kind: .photo, sortOrder: 20),
                    .init(id: "measurements", label: "Measurements", kind: .measurement, sortOrder: 30),
                ]
            ),
            SiteVisitType(
                id: "system-\(companyId)-deck-estimate",
                companyId: companyId,
                slug: "deck_estimate",
                name: "Deck Estimate",
                descriptionText: "Deck scope, photos, measurements, and design.",
                isSystemTemplate: true,
                sortOrder: 10,
                fields: deckFields
            ),
            SiteVisitType(
                id: "system-\(companyId)-repair-inspection",
                companyId: companyId,
                slug: "repair_inspection",
                name: "Repair Inspection",
                descriptionText: "Defect, cause, access, and photo evidence.",
                isSystemTemplate: true,
                sortOrder: 20,
                fields: [
                    .init(id: "reported-issue", label: "Reported issue", kind: .longText, required: true, sortOrder: 10),
                    .init(id: "cause", label: "Likely cause", kind: .shortText, sortOrder: 20),
                    .init(id: "repair-photos", label: "Repair photos", kind: .photoMarkup, required: true, sortOrder: 30),
                    .init(id: "access", label: "Access clear", kind: .yesNoNA, sortOrder: 40),
                ]
            ),
        ]
    }
}

@Model
final class SiteVisitChecklistAnswer: Identifiable {
    @Attribute(.unique) var id: String
    var siteVisitId: String
    var companyId: String
    var opportunityId: String?
    var siteVisitTypeId: String?
    var fieldId: String
    var label: String
    var kind: SiteVisitFieldKind
    var required: Bool
    var helpText: String?
    var sortOrder: Int
    var answerValueData: Data?
    var createdBy: String?
    var createdAt: Date
    var updatedAt: Date?
    var deletedAt: Date?
    var needsSync: Bool
    var lastSyncedAt: Date?

    init(
        id: String = UUID().uuidString,
        siteVisitId: String,
        companyId: String,
        opportunityId: String?,
        siteVisitTypeId: String?,
        fieldId: String,
        label: String,
        kind: SiteVisitFieldKind,
        required: Bool,
        helpText: String? = nil,
        sortOrder: Int,
        answerValue: SiteVisitChecklistValue = .empty,
        createdBy: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.siteVisitId = siteVisitId
        self.companyId = companyId
        self.opportunityId = opportunityId
        self.siteVisitTypeId = siteVisitTypeId
        self.fieldId = fieldId
        self.label = label
        self.kind = kind
        self.required = required
        self.helpText = helpText
        self.sortOrder = sortOrder
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.needsSync = true
        self.answerValue = answerValue
    }

    var answerValue: SiteVisitChecklistValue {
        get {
            guard let answerValueData,
                  let decoded = try? JSONDecoder().decode(
                    SiteVisitChecklistValue.self,
                    from: answerValueData
                  ) else { return .empty }
            return decoded
        }
        set {
            answerValueData = try? JSONEncoder().encode(newValue)
            updatedAt = Date()
            needsSync = true
        }
    }

    var isActive: Bool {
        deletedAt == nil
    }

    var isAnswered: Bool {
        answerValue.isAnswered
    }

    static func makeAnswers(
        for siteVisitType: SiteVisitType,
        siteVisitId: String,
        companyId: String,
        opportunityId: String?,
        createdBy: String?
    ) -> [SiteVisitChecklistAnswer] {
        siteVisitType.fields.map { field in
            SiteVisitChecklistAnswer(
                siteVisitId: siteVisitId,
                companyId: companyId,
                opportunityId: opportunityId,
                siteVisitTypeId: siteVisitType.id,
                fieldId: field.id,
                label: field.label,
                kind: field.kind,
                required: field.required,
                helpText: field.helpText,
                sortOrder: field.sortOrder,
                createdBy: createdBy
            )
        }
    }
}
