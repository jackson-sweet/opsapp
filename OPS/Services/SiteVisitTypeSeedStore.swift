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
        // Seeding creates missing templates only. Opening capture is never
        // authority to rewrite a company's saved labels, kinds or defaults.
        var inserted: [SiteVisitType] = []
        for canonical in builtIns where existingBySlug[canonical.slug] == nil {
            if existing.contains(where: { $0.isDefault && $0.deletedAt == nil }) { canonical.isDefault = false }
            context.insert(canonical)
            inserted.append(canonical)
        }
        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        let unsent = (existing + inserted).filter { type in
            type.lastSyncedAt == nil && !operations.contains { operation in
                operation.status != "completed" && (
                    operation.entityId.lowercased() == type.id.lowercased() ||
                    SiteVisitVersionedSync.command(operation)?.rows.contains(where: { $0.id == type.id.lowercased() }) == true)
            }
        }
        var queuedWork = false
        if canManageTemplates && !unsent.isEmpty {
            try SiteVisitVersionedSync.enqueueTemplates(unsent, context: context)
            queuedWork = true
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
