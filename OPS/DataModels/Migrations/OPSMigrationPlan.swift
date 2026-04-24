//
//  OPSMigrationPlan.swift
//  OPS
//
//  Declares the ordered sequence of SwiftData schema migrations that can
//  bring any previously-shipped OPS store forward to the current schema.
//
//  V1 → V2 stage: `WizardState` gains a mandatory `id` primary key used by
//  the Supabase sync layer. Existing rows predate that column, so the
//  custom `didMigrate` closure backfills a fresh UUID for every row whose
//  `id` is empty after the schema transform. Uniqueness is preserved
//  because every row receives its own UUID.
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

    /// Populates `WizardState.id` for every row that existed before the sync
    /// contract introduced the column. Runs once per device the first time
    /// the user launches a V2 build over a V1 store.
    static let migrateWizardStateIdV1toV2 = MigrationStage.custom(
        fromVersion: OPSSchemaV1.self,
        toVersion: OPSSchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
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
