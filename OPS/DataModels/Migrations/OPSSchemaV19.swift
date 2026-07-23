//
//  OPSSchemaV19.swift
//  OPS
//
//  Schema version 19.0.0 — reversible lead ownership correction.
//
//  Opportunity gains the optional `operatorActionRequiredAt` event timestamp.
//  V18 retains its frozen released shape (`OPSSchemaLegacyOpportunityV18`) so
//  installed stores remain recognizable. The widened live Opportunity begins
//  here; historical rows receive nil through an adjacent lightweight migration.
//

import Foundation
import SwiftData

enum OPSSchemaV19: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(19, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v19OpportunityModel
            + OPSSchemaCommon.v16DeckDesignModel
            + OPSSchemaCommon.v13ProjectNoteModel
            + OPSSchemaCommon.v18PhotoAnnotationModel
            + OPSSchemaCommon.v13ActivityModel
            + OPSSchemaCommon.v14SiteVisitModel
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
            + OPSSchemaCommon.v12SiteVisitIdentityModels
            + [WizardState.self, CalendarMirrorMap.self]
    }
}
