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

import Foundation
import SwiftData

enum OPSMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [OPSSchemaV1.self, OPSSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateWizardStateIdV1toV2]
    }

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
