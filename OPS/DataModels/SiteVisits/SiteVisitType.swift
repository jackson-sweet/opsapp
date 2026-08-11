//
//  SiteVisitType.swift
//  OPS
//
//  Company-scoped site visit templates and per-visit checklist answer snapshots.
//

import Foundation
import SwiftData

enum SiteVisitFieldKind: String, Codable, CaseIterable, Hashable, Sendable {
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

struct SiteVisitTypeFieldDefinition: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var label: String
    var kind: SiteVisitFieldKind
    var required: Bool
    var helpText: String?
    var sortOrder: Int
    /// Optional for wire compatibility with checklist definitions written by
    /// older builds. A missing value means shown.
    var isVisible: Bool?

    init(
        id: String = UUID().uuidString,
        label: String,
        kind: SiteVisitFieldKind,
        required: Bool = false,
        helpText: String? = nil,
        isVisible: Bool = true,
        sortOrder: Int
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.required = required
        self.helpText = helpText
        self.isVisible = isVisible
        self.sortOrder = sortOrder
    }

    var isShown: Bool {
        isVisible != false
    }
}

enum SiteVisitTypeTemplateReconciler {
    /// Field ids the product shipped in an earlier canonical template and has
    /// since retired. By id alone these are indistinguishable from a company's
    /// own additions (which use UUID ids), so reconciliation needs this ledger
    /// to drop them from stored company copies — otherwise every company
    /// seeded before the retirement keeps the dead row forever.
    /// "field-measurements" left the deck checklist on 2026-07-29 (e97e7209).
    static let retiredFieldIds: Set<String> = ["field-measurements"]

    /// Refreshes product-owned field metadata without undoing a company's
    /// visibility, required, or ordering choices. Company-added fields remain
    /// in place, retired product fields are dropped, and newly shipped
    /// canonical fields are appended.
    static func reconciledFields(
        existing: [SiteVisitTypeFieldDefinition],
        canonical: [SiteVisitTypeFieldDefinition]
    ) -> [SiteVisitTypeFieldDefinition] {
        let canonicalById = Dictionary(uniqueKeysWithValues: canonical.map { ($0.id, $0) })
        let kept = existing.filter { !retiredFieldIds.contains($0.id) }
        let keptIds = Set(kept.map(\.id))

        var result = kept.map { field in
            guard let productField = canonicalById[field.id] else { return field }
            var merged = field
            merged.label = productField.label
            merged.kind = productField.kind
            merged.helpText = productField.helpText
            return merged
        }

        result.append(contentsOf: canonical.filter { !keptIds.contains($0.id) })
        return result.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder { return lhs.id < rhs.id }
            return lhs.sortOrder < rhs.sortOrder
        }
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
        self.needsSync = true
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
            needsSync = true
        }
    }

    /// Trade-agnostic starter visit types. Every subtrade does these three;
    /// the deck-specific type is only seeded for companies running the deck
    /// builder (CanPro). Companies can add their own types on top of these.
    static func builtInTemplates(
        companyId: String,
        deckBuilderEnabled: Bool
    ) -> [SiteVisitType] {
        var templates: [SiteVisitType] = [
            // The default: scoping a job to quote it.
            SiteVisitType(
                id: "system-\(companyId)-estimate",
                companyId: companyId,
                slug: "estimate",
                name: "Estimate",
                descriptionText: "Scope a job to quote it.",
                isSystemTemplate: true,
                isDefault: true,
                sortOrder: 0,
                fields: [
                    .init(id: "scope-of-work", label: "Scope of work", kind: .longText, required: true, sortOrder: 10),
                    .init(id: "site-photos", label: "Site photos", kind: .photo, sortOrder: 20),
                    .init(id: "measurements", label: "Measurements", kind: .measurement, sortOrder: 30),
                    .init(id: "access-parking", label: "Access & parking", kind: .shortText, helpText: "Gate codes, parking, pets", sortOrder: 40),
                    .init(id: "client-priorities", label: "What the client wants", kind: .longText, sortOrder: 50),
                ]
            ),
            // Diagnose / repair a reported problem.
            SiteVisitType(
                id: "system-\(companyId)-service-call",
                companyId: companyId,
                slug: "service_call",
                name: "Service Call",
                descriptionText: "Diagnose and fix a reported issue.",
                isSystemTemplate: true,
                sortOrder: 10,
                fields: [
                    .init(id: "reported-issue", label: "Reported issue", kind: .longText, required: true, sortOrder: 10),
                    .init(id: "service-photos", label: "Photos", kind: .photo, sortOrder: 20),
                    .init(id: "work-done", label: "Work done & findings", kind: .longText, sortOrder: 30),
                    .init(id: "return-needed", label: "Return visit needed", kind: .yesNoNA, sortOrder: 40),
                ]
            ),
            // Take-offs for an install.
            SiteVisitType(
                id: "system-\(companyId)-measure-survey",
                companyId: companyId,
                slug: "measure_survey",
                name: "Measure / Survey",
                descriptionText: "Take measurements and document conditions.",
                isSystemTemplate: true,
                sortOrder: 20,
                fields: [
                    .init(id: "measurements", label: "Measurements", kind: .measurement, required: true, sortOrder: 10),
                    .init(id: "site-photos", label: "Site photos", kind: .photo, sortOrder: 20),
                    .init(id: "conditions", label: "Conditions & obstructions", kind: .longText, sortOrder: 30),
                ]
            ),
        ]

        if deckBuilderEnabled {
            templates.append(
                SiteVisitType(
                    id: "system-\(companyId)-deck-estimate",
                    companyId: companyId,
                    slug: "deck_estimate",
                    name: "Deck",
                    descriptionText: "Deck scope, photos, measurements, and design.",
                    isSystemTemplate: true,
                    sortOrder: 30,
                    fields: [
                        .init(id: "client-goals", label: "What the client wants", kind: .longText, sortOrder: 10),
                        .init(id: "existing-structure", label: "Existing structure", kind: .photoMarkup, sortOrder: 20),
                        // No measurement row: measuring is what the visit's
                        // capture tools are for (LiDAR / scaled / dimensioned).
                        // A checklist item demanding the same thing was a second
                        // gate that blocked completion after the work was done.
                        .init(id: "deck-design", label: "Deck design", kind: .deckDesign, required: true, sortOrder: 40),
                    ]
                )
            )
        }

        return templates
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
        self.id = id.lowercased()
        self.siteVisitId = siteVisitId.lowercased()
        self.companyId = companyId.lowercased()
        self.opportunityId = opportunityId?.lowercased()
        self.siteVisitTypeId = siteVisitTypeId
        self.fieldId = fieldId
        self.label = label
        self.kind = kind
        self.required = required
        self.helpText = helpText
        self.sortOrder = sortOrder
        self.createdBy = createdBy?.lowercased()
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
        siteVisitType.fields.filter(\.isShown).map { field in
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
