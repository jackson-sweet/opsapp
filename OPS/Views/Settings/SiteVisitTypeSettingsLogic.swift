//
//  SiteVisitTypeSettingsLogic.swift
//  OPS
//
//  Pure editor draft validation and normalization.
//

import Foundation

struct SiteVisitTypeDraft: Identifiable {
    var id: String?
    var slug: String?
    var name: String
    var descriptionText: String
    var isSystemTemplate: Bool
    var isDefault: Bool
    var fields: [SiteVisitTypeFieldDefinition]

    static let blank = SiteVisitTypeDraft(
        id: nil,
        slug: nil,
        name: "",
        descriptionText: "",
        isSystemTemplate: false,
        isDefault: false,
        fields: []
    )

    init(
        id: String?,
        slug: String?,
        name: String,
        descriptionText: String,
        isSystemTemplate: Bool,
        isDefault: Bool,
        fields: [SiteVisitTypeFieldDefinition]
    ) {
        self.id = id
        self.slug = slug
        self.name = name
        self.descriptionText = descriptionText
        self.isSystemTemplate = isSystemTemplate
        self.isDefault = isDefault
        self.fields = fields
    }

    init(type: SiteVisitType) {
        self.init(
            id: type.id,
            slug: type.slug,
            name: type.name,
            descriptionText: type.descriptionText ?? "",
            isSystemTemplate: type.isSystemTemplate,
            isDefault: type.isDefault,
            fields: type.fields
        )
    }
}

enum SiteVisitTypeSettingsError: LocalizedError, Equatable {
    case unavailable
    case permissionDenied
    case companyMismatch
    case nameRequired
    case nameTooLong
    case descriptionTooLong
    case fieldLimitReached
    case fieldLabelRequired
    case fieldLabelTooLong
    case helpTextTooLong
    case visibleFieldRequired
    case systemTypeProtected
    case finalTypeProtected

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Site visit types are unavailable."
        case .permissionDenied: return "You do not have permission to edit company checklists."
        case .companyMismatch: return "This visit type belongs to another company."
        case .nameRequired: return "Enter a visit type name."
        case .nameTooLong: return "Keep the visit type name under 120 characters."
        case .descriptionTooLong: return "Keep the description under 500 characters."
        case .fieldLimitReached: return "A checklist can have up to 100 fields."
        case .fieldLabelRequired: return "Every checklist field needs a label."
        case .fieldLabelTooLong: return "Keep field labels under 500 characters."
        case .helpTextTooLong: return "Keep field guidance under 2,000 characters."
        case .visibleFieldRequired: return "Keep at least one checklist field shown."
        case .systemTypeProtected: return "Built-in visit types cannot be deleted."
        case .finalTypeProtected: return "Keep at least one site visit type."
        }
    }
}

enum SiteVisitTypeSettingsLogic {
    static let maximumNameLength = 120
    static let maximumDescriptionLength = 500
    static let maximumFieldCount = 100
    static let maximumFieldLabelLength = 500
    static let maximumHelpTextLength = 2_000

    static func normalizedName(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw SiteVisitTypeSettingsError.nameRequired
        }
        guard normalized.count <= maximumNameLength else {
            throw SiteVisitTypeSettingsError.nameTooLong
        }
        return normalized
    }

    static func normalizedDescription(_ value: String) throws -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count <= maximumDescriptionLength else {
            throw SiteVisitTypeSettingsError.descriptionTooLong
        }
        return normalized.isEmpty ? nil : normalized
    }

    static func normalizedFields(
        _ fields: [SiteVisitTypeFieldDefinition]
    ) throws -> [SiteVisitTypeFieldDefinition] {
        guard !fields.isEmpty else {
            throw SiteVisitTypeSettingsError.visibleFieldRequired
        }
        guard fields.count <= maximumFieldCount else {
            throw SiteVisitTypeSettingsError.fieldLimitReached
        }

        var normalized: [SiteVisitTypeFieldDefinition] = []
        for (index, field) in fields.enumerated() {
            var copy = field
            copy.label = field.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !copy.label.isEmpty else {
                throw SiteVisitTypeSettingsError.fieldLabelRequired
            }
            guard copy.label.count <= maximumFieldLabelLength else {
                throw SiteVisitTypeSettingsError.fieldLabelTooLong
            }
            copy.helpText = field.helpText?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if copy.helpText?.isEmpty == true { copy.helpText = nil }
            guard (copy.helpText?.count ?? 0) <= maximumHelpTextLength else {
                throw SiteVisitTypeSettingsError.helpTextTooLong
            }
            copy.sortOrder = (index + 1) * 10
            if !copy.isShown {
                copy.required = false
                copy.isVisible = false
            } else {
                copy.isVisible = true
            }
            normalized.append(copy)
        }

        guard normalized.contains(where: \.isShown) else {
            throw SiteVisitTypeSettingsError.visibleFieldRequired
        }
        return normalized
    }
}
