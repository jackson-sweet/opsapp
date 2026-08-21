//
//  OPSSchemaV25.swift
//  OPS
//
//  Schema version 25.0.0 — project primary sub-contact projection.
//
//  Adds an independent local projection for the server's nullable
//  `projects.primary_sub_client_id`. Project itself stays byte-for-byte
//  compatible with V24 so installed stores remain recognizable.
//

import Foundation
import SwiftData

enum OPSSchemaV25: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(25, 0, 0) }

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
            + [
                WizardState.self,
                CalendarMirrorMap.self,
                ProjectPrimaryContactSelection.self
            ]
    }
}
