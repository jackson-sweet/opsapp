//
//  OPSMigrationPlan.swift
//  OPS
//
//  Declares the ordered sequence of SwiftData schema migrations that can
//  bring any previously-shipped OPS store forward to the current schema.
//
//  V1 → V2 stage: `WizardState` gains a mandatory `id` primary key used by
//  the Supabase sync layer. SwiftData's automatic schema transform refuses
//  to add a non-optional column to existing rows because there is no value
//  to populate — that's the NSCocoaErrorDomain 134110 the previous attempt
//  hit. `MigrationStage.custom` does NOT bypass this validation: `didMigrate`
//  only runs *after* the schema transform succeeds.
//
//  We fix it by clearing legacy WizardState rows in `willMigrate` (V1
//  context), so the schema transform runs against an empty table. Wizard
//  state is tutorial-progress only and is re-hydrated on next launch by
//  `InboundProcessor.syncWizardStates`, with `WizardStateManager` lazily
//  creating fresh `not_started` rows for any wizard the server has no record
//  of. The `didMigrate` UUID backfill is kept as defense-in-depth in case a
//  row somehow lands in V2 with an empty id.
//
//  V2 → V3 stage: drops the legacy `Inventory*` entities and registers the
//  new `catalog_*` / `product_*` extension entities. The schema diff itself
//  performs the destructive work (SwiftData removes records of entity types
//  absent from the new schema), so `willMigrate` has nothing to do. We set
//  `needs_full_catalog_sync` in `didMigrate` so InboundProcessor pulls a
//  fresh full catalog on next launch.
//
//  V3 → V4 stage: lightweight additive — TaskTypeReminder + TaskReminder.
//
//  V4 → V5 stage: lightweight additive — CalendarMirrorMap for the iPhone
//  Calendar Mirror feature. Originally landed as V3 on the calendar-mirror
//  branch; renumbered to V5 during the catalog-variant-model merge.
//
//  V5 → V6 stage: lightweight additive — PaymentMilestone (iOS parity for
//  the existing server table) and RecurringExpense (new) for the Cashflow
//  Forecast feature. Spec at docs/superpowers/specs/2026-05-11-cashflow-forecast-design.md.
//
//  V6 → V7 stage: lightweight additive — ProjectVinylOrderMarker, a local
//  projection of the project-level vinyl order marker fields.
//
//  V7 → V8 stage: lightweight additive — catalog stock units and
//  catalog-product option mappings for Phase 4 Catalog Setup.
//
//  V8 → V9 stage: lightweight additive — `ProjectPhoto`, the synced
//  `project_photos` gallery store, so every assigned teammate sees the full
//  gallery instead of only the uploader's optimistic local append.
//

import Foundation
import SwiftData

enum OPSMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            OPSSchemaV1.self,
            OPSSchemaV2.self,
            OPSSchemaV3.self,
            OPSSchemaV4.self,
            OPSSchemaV5.self,
            OPSSchemaV6.self,
            OPSSchemaV7.self,
            OPSSchemaV8.self,
            OPSSchemaV9.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            migrateWizardStateIdV1toV2,
            migrateInventoryToCatalogV2toV3,
            migrateAddTaskRemindersV3toV4,
            addCalendarMirrorMapV4toV5,
            addForecastModelsV5toV6,
            addVinylOrderMarkerV6toV7,
            addCatalogSetupModelsV7toV8,
            addProjectPhotosV8toV9
        ]
    }

    /// V8 → V9: purely additive — `ProjectPhoto` is a brand-new @Model backing
    /// the synced `project_photos` gallery store. No pre-existing rows to
    /// transform; SwiftData lightweight migration handles the V8 store.
    static let addProjectPhotosV8toV9 = MigrationStage.lightweight(
        fromVersion: OPSSchemaV8.self,
        toVersion: OPSSchemaV9.self
    )

    /// V7 → V8: purely additive — stock units and product-option mappings are
    /// new local projections of existing live catalog setup tables.
    static let addCatalogSetupModelsV7toV8 = MigrationStage.lightweight(
        fromVersion: OPSSchemaV7.self,
        toVersion: OPSSchemaV8.self
    )

    /// V6 → V7: purely additive — `ProjectVinylOrderMarker` is a local
    /// projection of server columns on `projects`, with no rows to transform
    /// before the next project sync hydrates it.
    static let addVinylOrderMarkerV6toV7 = MigrationStage.lightweight(
        fromVersion: OPSSchemaV6.self,
        toVersion: OPSSchemaV7.self
    )

    /// V5 → V6: purely additive — `PaymentMilestone` and `RecurringExpense` are
    /// new models with no pre-existing rows to transform. SwiftData lightweight
    /// migration handles the schema diff transparently.
    static let addForecastModelsV5toV6 = MigrationStage.lightweight(
        fromVersion: OPSSchemaV5.self,
        toVersion: OPSSchemaV6.self
    )

    /// V4 → V5: purely additive — `CalendarMirrorMap` is a brand-new model
    /// with no pre-existing rows to transform. SwiftData lightweight migration
    /// handles it.
    static let addCalendarMirrorMapV4toV5 = MigrationStage.lightweight(
        fromVersion: OPSSchemaV4.self,
        toVersion: OPSSchemaV5.self
    )

    /// V3 → V4 adds the TaskTypeReminder and TaskReminder entities plus inverse
    /// `reminderTemplates` / `reminders` arrays on TaskType and ProjectTask.
    /// Purely additive — no destructive transforms — so SwiftData lightweight
    /// migration handles the schema diff transparently.
    static let migrateAddTaskRemindersV3toV4 = MigrationStage.lightweight(
        fromVersion: OPSSchemaV3.self,
        toVersion: OPSSchemaV4.self
    )

    /// V2 → V3 drops the legacy Inventory* entities and registers the new
    /// catalog_* / product_* extension entities, then flags InboundProcessor
    /// to pull a fresh full catalog sync on next launch.
    static let migrateInventoryToCatalogV2toV3 = MigrationStage.custom(
        fromVersion: OPSSchemaV2.self,
        toVersion: OPSSchemaV3.self,
        willMigrate: { _ in
            // Intentionally empty. SwiftData drops entity types absent from the new
            // schema during the schema transform itself; nothing for us to do here.
            // The new catalog/product-extension entities will be empty until the
            // next inbound sync runs.
        },
        didMigrate: { _ in
            // Force a fresh full-sync flag so InboundProcessor pulls all
            // catalog data on next launch.
            UserDefaults.standard.set(true, forKey: "needs_full_catalog_sync")
        }
    )

    /// Bridges the pre-`id` WizardState shape into the V2 schema by dropping
    /// every legacy row before the schema transform runs, then defensively
    /// stamping any survivor that lands in V2 without an id.
    static let migrateWizardStateIdV1toV2 = MigrationStage.custom(
        fromVersion: OPSSchemaV1.self,
        toVersion: OPSSchemaV2.self,
        willMigrate: { context in
            // V1 context — fetch the nested legacy type, not the top-level
            // V2 `WizardState`. The legacy rows lack the mandatory `id`
            // column added in V2, so there is no value SwiftData can use to
            // satisfy the transform; deleting them is the only safe path.
            let descriptor = FetchDescriptor<OPSSchemaV1.WizardState>()
            let legacy = try context.fetch(descriptor)
            for state in legacy {
                context.delete(state)
            }
            try context.save()
        },
        didMigrate: { context in
            // Defensive: if any row reaches V2 with an empty id (shouldn't
            // happen given the willMigrate sweep), assign a fresh UUID and
            // mark the row for re-sync so the server learns about it.
            let descriptor = FetchDescriptor<WizardState>()
            let states = try context.fetch(descriptor)
            for state in states where state.id.isEmpty {
                state.id = UUID().uuidString
                state.needsSync = true
            }
            try context.save()
        }
    )
}
