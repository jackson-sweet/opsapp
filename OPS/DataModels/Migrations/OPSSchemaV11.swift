//
//  OPSSchemaV11.swift
//  OPS
//
//  Schema version 11.0.0 — Site visit capture packet.
//
//  V11 adds the local pre-project site-visit packet: captured evidence,
//  company-scoped visit types, and per-visit checklist answer snapshots. It
//  keeps photos, notes, measurements, LiDAR dimensioned captures, custom
//  checklist answers, and CanPro deck-design references together until the
//  operator reviews the packet and creates the project.
//
//  Purely additive over V10. No existing rows need transformation.
//

import Foundation
import SwiftData

enum OPSSchemaV11: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(11, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v11SiteVisitModel
            + OPSSchemaCommon.v4CoreModels
            + OPSSchemaCommon.v4TaskModels
            + OPSSchemaCommon.v8CatalogModels
            + OPSSchemaCommon.v4ReminderModels
            + OPSSchemaCommon.v6ForecastModels
            + OPSSchemaCommon.v7VinylOrderModels
            + OPSSchemaCommon.v8CatalogSetupModels
            + OPSSchemaCommon.v9ProjectPhotoModels
            + OPSSchemaCommon.v10StockUnitEventModels
            + OPSSchemaCommon.v11SiteVisitCaptureModels
            + [WizardState.self, CalendarMirrorMap.self]
    }
}
