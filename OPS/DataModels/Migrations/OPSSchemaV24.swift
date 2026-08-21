//
//  OPSSchemaV24.swift
//  OPS
//
//  Schema version 24.0.0 — Phase C appointment presentation metadata.
//
//  `SiteVisit` gains four nullable server-owned attributes that preserve the
//  exact bilateral appointment identity, kind, title, and location across
//  local schedule rendering and EventKit mirrors. V23 is frozen at its
//  released fingerprint and migrates here through one lightweight stage.
//

import Foundation
import SwiftData

enum OPSSchemaV24: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(24, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v19OpportunityModel
            + OPSSchemaCommon.v16DeckDesignModel
            + OPSSchemaCommon.v13ProjectNoteModel
            + OPSSchemaCommon.v18PhotoAnnotationModel
            + OPSSchemaCommon.v22ActivityModel
            + OPSSchemaCommon.v24SiteVisitModel
            + OPSSchemaCommon.v4CoreModels
            + OPSSchemaCommon.v4TaskModels
            + OPSSchemaCommon.v8CatalogModels
            + OPSSchemaCommon.v4ReminderModels
            + OPSSchemaCommon.v6ForecastModels
            + OPSSchemaCommon.v17VinylOrderModel
            + OPSSchemaCommon.v8CatalogSetupModels
            + OPSSchemaCommon.v9ProjectPhotoModels
            + OPSSchemaCommon.v10StockUnitEventModels
            + OPSSchemaCommon.v11SiteVisitCaptureModels
            + OPSSchemaCommon.v20SiteVisitIdentityModels
            + [WizardState.self, CalendarMirrorMap.self]
    }
}
