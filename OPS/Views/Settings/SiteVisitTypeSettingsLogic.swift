//
//  SiteVisitTypeSettingsLogic.swift
//  OPS
//
//  Pure editor draft validation and normalization.
//

import Foundation

/// UI choices are separate from the persisted eight-kind wire enum.
enum SiteVisitFieldInputType: Hashable {
    case standard(SiteVisitFieldKind)
    case singleChoice

    var settingsName: String {
        switch self {
        case .singleChoice: return "Multiple choice"
        case .standard(let kind):
            switch kind {
            case .checkbox: return "Checkbox"
            case .yesNoNA: return "Yes / No / N/A"
            case .shortText: return "Short answer"
            case .longText: return "Long answer"
            case .measurement: return "Measurement"
            case .photo: return "Photo"
            case .photoMarkup: return "Photo + markup"
            case .deckDesign: return "Deck design"
            }
        }
    }
}

extension SiteVisitTypeFieldDefinition {
    var inputType: SiteVisitFieldInputType {
        get { singleChoice == nil ? .standard(kind) : .singleChoice }
        set {
            switch newValue {
            case .standard(let kind): self.kind = kind; singleChoice = nil
            case .singleChoice:
                kind = .shortText
                if singleChoice == nil {
                    singleChoice = .init(options: [.init(label: ""), .init(label: "")])
                }
            }
        }
    }
}

struct SiteVisitTypeDraft: Identifiable {
    var id: String?
    var slug: String?
    var name: String
    var descriptionText: String
    var isSystemTemplate: Bool
    var isDefault: Bool
    var fields: [SiteVisitTypeFieldDefinition]
    var originalWriteState: SiteVisitWriteState?

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
        var state = type.writeState
        state.begin(SiteVisitWriteModels.values(type))
        originalWriteState = state
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

    static func availableInputTypes(deckBuilderEnabled: Bool, preserving kind: SiteVisitFieldKind) -> [SiteVisitFieldInputType] {
        var types = availableFieldKinds(deckBuilderEnabled: deckBuilderEnabled, preserving: kind).map(SiteVisitFieldInputType.standard)
        types.insert(.singleChoice, at: 2)
        return types
    }

    static func availableFieldKinds(
        deckBuilderEnabled: Bool,
        preserving currentKind: SiteVisitFieldKind? = nil
    ) -> [SiteVisitFieldKind] {
        var kinds: [SiteVisitFieldKind] = [
            .checkbox,
            .yesNoNA,
            .shortText,
            .longText,
            .measurement,
            .photo,
            .photoMarkup,
        ]

        if deckBuilderEnabled || currentKind == .deckDesign {
            kinds.append(.deckDesign)
        }

        return kinds
    }

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
            if let singleChoice = field.singleChoice {
                guard field.kind == .shortText else { throw SiteVisitSingleChoice.ValidationError.invalidDefinition }
                copy.singleChoice = try singleChoice.normalized()
            }
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
