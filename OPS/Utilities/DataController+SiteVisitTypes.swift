//
//  DataController+SiteVisitTypes.swift
//  OPS
//
//  Local-first site-visit template administration and durable queue writes.
//

import Foundation
import SwiftData

extension DataController {
    @MainActor
    @discardableResult
    func ensureSiteVisitTypesSeeded(deckBuilderEnabled: Bool) throws -> [SiteVisitType] {
        guard let context = modelContext,
              let companyId = currentUser?.companyId,
              !companyId.isEmpty else {
            throw SiteVisitTypeSettingsError.unavailable
        }

        let canonicalCompanyId = companyId.lowercased()
        let existing = try context.fetch(FetchDescriptor<SiteVisitType>()).filter {
            $0.companyId.lowercased() == canonicalCompanyId
        }
        let builtIns = SiteVisitType.builtInTemplates(
            companyId: canonicalCompanyId,
            deckBuilderEnabled: deckBuilderEnabled
        )
        var existingBySlug: [String: SiteVisitType] = [:]
        for type in existing {
            let current = existingBySlug[type.slug]
            if current == nil || (current?.isSystemTemplate == false && type.isSystemTemplate) {
                existingBySlug[type.slug] = type
            }
        }
        var mutations: [(SiteVisitType, String)] = []

        for canonical in builtIns {
            if let type = existingBySlug[canonical.slug], type.isSystemTemplate {
                let reconciled = SiteVisitTypeTemplateReconciler.reconciledFields(
                    existing: type.fields,
                    canonical: canonical.fields
                )
                let needsMetadataRefresh = type.name != canonical.name
                    || type.descriptionText != canonical.descriptionText
                    || type.sortOrder != canonical.sortOrder
                    || type.fields != reconciled
                if needsMetadataRefresh {
                    type.name = canonical.name
                    type.descriptionText = canonical.descriptionText
                    type.sortOrder = canonical.sortOrder
                    type.fields = reconciled
                    type.needsSync = true
                    mutations.append((type, type.lastSyncedAt == nil ? "create" : "update"))
                } else if type.lastSyncedAt == nil {
                    mutations.append((type, "create"))
                }
            } else if existingBySlug[canonical.slug] == nil {
                context.insert(canonical)
                mutations.append((canonical, "create"))
            }
        }

        let builtInSlugs = Set(builtIns.map(\.slug))
        for type in existing where type.isSystemTemplate
            && type.deletedAt == nil
            && !builtInSlugs.contains(type.slug) {
            type.deletedAt = Date()
            type.updatedAt = Date()
            type.needsSync = true
            mutations.append((type, "delete"))
        }

        try context.save()
        let canManageTemplates = PermissionStore.shared.can("settings.company")
        if canManageTemplates {
            for (type, operation) in mutations {
                try queueSiteVisitType(type, operationType: operation)
            }
        }
        if !mutations.isEmpty {
            NotificationCenter.default.post(
                name: .siteVisitTypesChanged,
                object: nil
            )
            if canManageTemplates {
                Task { await syncEngine.triggerSync() }
            }
        }
        return try activeSiteVisitTypes(companyId: canonicalCompanyId, context: context)
    }

    @MainActor
    @discardableResult
    func saveSiteVisitType(_ draft: SiteVisitTypeDraft) throws -> SiteVisitType {
        guard let context = modelContext,
              let companyId = currentUser?.companyId,
              !companyId.isEmpty else {
            throw SiteVisitTypeSettingsError.unavailable
        }
        guard PermissionStore.shared.can("settings.company") else {
            throw SiteVisitTypeSettingsError.permissionDenied
        }
        let canonicalCompanyId = companyId.lowercased()
        let name = try SiteVisitTypeSettingsLogic.normalizedName(draft.name)
        let descriptionText = try SiteVisitTypeSettingsLogic
            .normalizedDescription(draft.descriptionText)
        let fields = try SiteVisitTypeSettingsLogic.normalizedFields(draft.fields)
        let active = try activeSiteVisitTypes(
            companyId: canonicalCompanyId,
            context: context
        )

        let type: SiteVisitType
        let operationType: String
        if let draftId = draft.id?.lowercased() {
            guard let existing = active.first(where: {
                $0.id.lowercased() == draftId
            }) else {
                throw SiteVisitTypeSettingsError.unavailable
            }
            guard existing.companyId.lowercased() == canonicalCompanyId else {
                throw SiteVisitTypeSettingsError.companyMismatch
            }
            type = existing
            operationType = existing.lastSyncedAt == nil ? "create" : "update"
            if !existing.isSystemTemplate {
                existing.name = name
                existing.descriptionText = descriptionText
            }
        } else {
            let id = UUID().uuidString.lowercased()
            type = SiteVisitType(
                id: id,
                companyId: canonicalCompanyId,
                slug: "custom_\(id.replacingOccurrences(of: "-", with: ""))",
                name: name,
                descriptionText: descriptionText,
                isDefault: active.isEmpty || draft.isDefault,
                sortOrder: (active.map(\.sortOrder).max() ?? -10) + 10,
                fields: fields
            )
            context.insert(type)
            operationType = "create"
        }

        type.fields = fields
        let keepExistingDefault = type.isDefault && !draft.isDefault
        type.isDefault = draft.isDefault || keepExistingDefault || active.isEmpty
        type.updatedAt = Date()
        type.needsSync = true

        var displacedDefaults: [SiteVisitType] = []
        if type.isDefault {
            for other in active where other.id != type.id && other.isDefault {
                other.isDefault = false
                other.updatedAt = Date()
                other.needsSync = true
                displacedDefaults.append(other)
            }
        }

        try context.save()
        for displaced in displacedDefaults {
            try queueSiteVisitType(displaced, operationType: "update")
        }
        try queueSiteVisitType(type, operationType: operationType)
        NotificationCenter.default.post(name: .siteVisitTypesChanged, object: nil)
        Task { await syncEngine.triggerSync() }
        return type
    }

    @MainActor
    func deleteSiteVisitType(_ id: String) throws {
        guard let context = modelContext,
              let companyId = currentUser?.companyId else {
            throw SiteVisitTypeSettingsError.unavailable
        }
        guard PermissionStore.shared.can("settings.company") else {
            throw SiteVisitTypeSettingsError.permissionDenied
        }
        let active = try activeSiteVisitTypes(
            companyId: companyId.lowercased(),
            context: context
        )
        guard let type = active.first(where: {
            $0.id.caseInsensitiveCompare(id) == .orderedSame
        }) else {
            throw SiteVisitTypeSettingsError.unavailable
        }
        guard !type.isSystemTemplate else {
            throw SiteVisitTypeSettingsError.systemTypeProtected
        }
        guard active.count > 1 else {
            throw SiteVisitTypeSettingsError.finalTypeProtected
        }

        var replacementDefault: SiteVisitType?
        if type.isDefault, let replacement = active.first(where: { $0.id != type.id }) {
            replacement.isDefault = true
            replacement.updatedAt = Date()
            replacement.needsSync = true
            replacementDefault = replacement
        }
        type.deletedAt = Date()
        type.updatedAt = Date()
        type.needsSync = true
        try context.save()
        if let replacementDefault {
            try queueSiteVisitType(replacementDefault, operationType: "update")
        }
        syncEngine.recordOperation(
            entityType: .siteVisitType,
            entityId: type.id.lowercased(),
            operationType: "delete",
            changedFields: [:]
        )
        NotificationCenter.default.post(name: .siteVisitTypesChanged, object: nil)
        Task { await syncEngine.triggerSync() }
    }

    @MainActor
    func refreshSiteVisitTypes() async {
        await syncEngine.triggerSync()
    }

    @MainActor
    private func queueSiteVisitType(
        _ type: SiteVisitType,
        operationType: String
    ) throws {
        syncEngine.recordOperation(
            entityType: .siteVisitType,
            entityId: type.id.lowercased(),
            operationType: operationType,
            changedFields: try SiteVisitTypeSyncPayload.make(type)
        )
    }

    private func activeSiteVisitTypes(
        companyId: String,
        context: ModelContext
    ) throws -> [SiteVisitType] {
        try context.fetch(FetchDescriptor<SiteVisitType>())
            .filter {
                $0.companyId.lowercased() == companyId.lowercased()
                    && $0.deletedAt == nil
            }
            .sorted {
                if $0.sortOrder == $1.sortOrder { return $0.name < $1.name }
                return $0.sortOrder < $1.sortOrder
            }
    }
}

extension Notification.Name {
    static let siteVisitTypesChanged = Notification.Name("SiteVisitTypesChanged")
}
