//
//  OPSSchemaV4.swift
//  OPS
//
//  Schema version 4.0.0 — Task Reminders.
//
//  V4 adds two new @Model entities (TaskTypeReminder, TaskReminder) plus
//  inverse @Relationship array fields on TaskType (`reminderTemplates`) and
//  ProjectTask (`reminders`). Both additions are purely additive: SwiftData
//  lightweight migration handles the V3 store transparently because no
//  existing column is renamed, retyped, or made non-optional.
//
//  See docs/superpowers/specs/2026-05-10-task-reminders-design.md.
//

import Foundation
import SwiftData

enum OPSSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v4CoreModels
            + OPSSchemaCommon.v4TaskModels
            + OPSSchemaCommon.v3CatalogModels
            + OPSSchemaCommon.v4ReminderModels
            + [WizardState.self]
    }
}
