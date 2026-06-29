//
//  OPSSchemaV5.swift
//  OPS
//
//  Schema version 5.0.0 — iPhone Calendar Mirror.
//
//  V5 adds `CalendarMirrorMap`, the client-local side-table powering the
//  iPhone Calendar Mirror feature. Purely additive over V4: SwiftData
//  lightweight migration handles the V4 store transparently because no
//  existing column is renamed, retyped, or made non-optional.
//
//  Originally authored as V3 on the calendar-mirror branch; renumbered to
//  V5 during the catalog-variant-model merge to slot after catalog (V3) and
//  task reminders (V4). The model itself is unchanged.
//
//  See docs/superpowers/specs/2026-05-10-iphone-calendar-mirror-design.md.
//

import Foundation
import SwiftData

enum OPSSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v1ToV10SiteVisitModel
            + OPSSchemaCommon.v4CoreModels
            + OPSSchemaCommon.v4TaskModels
            + OPSSchemaCommon.v3CatalogModels
            + OPSSchemaCommon.v4ReminderModels
            + [WizardState.self, CalendarMirrorMap.self]
    }
}
