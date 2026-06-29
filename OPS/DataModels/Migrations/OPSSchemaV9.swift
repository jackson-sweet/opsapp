//
//  OPSSchemaV9.swift
//  OPS
//
//  Schema version 9.0.0 — Synced project photos.
//
//  V9 adds `ProjectPhoto`, the canonical company-wide gallery store backed by
//  the `project_photos` table. Until now iOS only ever read the legacy
//  `projects.project_images` CSV, which the uploader appended to optimistically
//  but teammates never received — so a crew member's photo showed in comments
//  (project_photos rows / annotations) yet was missing from the gallery on
//  every other device. Promoting `project_photos` to a synced entity fixes that.
//
//  Purely additive over V8 — no rename, retype, or drop. `ProjectPhoto` is a
//  brand-new @Model, so V9's persistent checksum diverges from V8 organically
//  (the same reason V6 minted a real new model) and SwiftData lightweight
//  migration handles the on-disk V8 store transparently.
//

import Foundation
import SwiftData

enum OPSSchemaV9: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(9, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v1ToV10SiteVisitModel
            + OPSSchemaCommon.v4CoreModels
            + OPSSchemaCommon.v4TaskModels
            + OPSSchemaCommon.v8CatalogModels
            + OPSSchemaCommon.v4ReminderModels
            + OPSSchemaCommon.v6ForecastModels
            + OPSSchemaCommon.v7VinylOrderModels
            + OPSSchemaCommon.v8CatalogSetupModels
            + OPSSchemaCommon.v9ProjectPhotoModels
            + [WizardState.self, CalendarMirrorMap.self]
    }
}
