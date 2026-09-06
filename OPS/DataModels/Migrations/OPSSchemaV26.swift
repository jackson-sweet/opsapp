//
//  OPSSchemaV26.swift
//  OPS
//
//  Deck drawing server merge base. V16–V25 retain their released graph;
//  this adjacent lightweight boundary introduces nullable syncedDrawingJSON.
//  Nil stays unknown: never seed an acknowledgement from unsent local content.
//

import Foundation
import SwiftData

enum OPSSchemaV26: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(26, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v19OpportunityModel
            + OPSSchemaCommon.v26DeckDesignModel
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
            + [
                WizardState.self,
                CalendarMirrorMap.self,
                ProjectPrimaryContactSelection.self
            ]
    }
}
