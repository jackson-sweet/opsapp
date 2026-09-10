import Foundation
import SwiftData

/// The real capture-entry seed path owns both template and outbox changes.
@MainActor
enum SiteVisitTypeSeedStore {
    struct Result { let didChange: Bool; let queuedWork: Bool }
    static func seed(from sharedContext: ModelContext, companyId: String, deckBuilderEnabled: Bool,
                     canManageTemplates: Bool, validateCommit: () throws -> Void = {}) throws -> Result {
        let context = ModelContext(sharedContext.container)
        context.autosaveEnabled = false
        let canonicalCompanyId = companyId.lowercased()
        let companies = [canonicalCompanyId, canonicalCompanyId.uppercased()]
        let existing = try context.fetch(FetchDescriptor<SiteVisitType>(predicate: #Predicate {
            companies.contains($0.companyId)
        }))
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


        let ids = Array(Set((existing + builtIns).map { $0.id.lowercased() }))
        let entity = SyncEntityType.siteVisitType.rawValue
        let statuses = ["pending", "inProgress", "failed", "parked", "declined"]
        var count = FetchDescriptor<SyncOperation>()
        count.includePendingChanges = false
        let operations = try context.fetchCount(count) == 0 ? [] : context.fetch(FetchDescriptor<SyncOperation>(
            predicate: #Predicate { $0.entityType == entity && ids.contains($0.entityId) && statuses.contains($0.status) }))
        let owners = Dictionary(grouping: operations, by: \.entityId)
        var queuedWork = false
        if canManageTemplates {
            for (type, operationType) in mutations {
                let fields = try SiteVisitTypeSyncPayload.make(type)
                let payload = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
                if let owner = owners[type.id.lowercased()]?.max(by: { $0.createdAt < $1.createdAt }) {
                    // Seed replay is never an operator retry of stopped work.
                    guard owner.status == "pending" || owner.status == "failed" else { continue }
                    if owner.payload == payload && owner.operationType == operationType { continue }
                    owner.payload = payload
                    if owner.operationType != "create" || operationType == "delete" { owner.operationType = operationType }
                    owner.changedFields = fields.keys.sorted().joined(separator: ",")
                } else {
                    context.insert(SyncOperation(entityType: entity, entityId: type.id.lowercased(),
                        operationType: operationType, payload: payload, changedFields: fields.keys.sorted()))
                }
                queuedWork = true
            }
        }
        let didChange = context.hasChanges
        if didChange {
            // Both local templates and queue entries commit together. A failure
            // releases only this isolated context; caller WIP is untouched.
            try validateCommit()
            try context.save()
        }
        return Result(didChange: didChange, queuedWork: queuedWork)
    }
}
