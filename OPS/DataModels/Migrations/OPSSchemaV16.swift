//
//  OPSSchemaV16.swift
//  OPS
//
//  Schema version 16.0.0 — app-update compatibility boundary.
//
//  V16 introduces persisted fields that landed after V15 had already shipped:
//  Opportunity gains images plus latitude/longitude, and DeckDesign gains an
//  optional opportunityId. V1–V15 retain frozen pre-addition shapes so stores
//  created by released binaries remain recognizable. The current live models
//  begin here, making both changes an adjacent lightweight migration.
//

import Foundation
import SwiftData

enum OPSSchemaV16: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(16, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v16ToV17OpportunityModel
            + OPSSchemaCommon.v16DeckDesignModel
            + OPSSchemaCommon.v13ProjectNoteModel
            + OPSSchemaCommon.v15ToV17PhotoAnnotationModel
            + OPSSchemaCommon.v13ActivityModel
            + OPSSchemaCommon.v14SiteVisitModel
            + OPSSchemaCommon.v4CoreModels
            + OPSSchemaCommon.v4TaskModels
            + OPSSchemaCommon.v8CatalogModels
            + OPSSchemaCommon.v4ReminderModels
            + OPSSchemaCommon.v6ForecastModels
            + OPSSchemaCommon.v7ToV16VinylOrderModel
            + OPSSchemaCommon.v8CatalogSetupModels
            + OPSSchemaCommon.v9ProjectPhotoModels
            + OPSSchemaCommon.v10StockUnitEventModels
            + OPSSchemaCommon.v11SiteVisitCaptureModels
            + OPSSchemaCommon.v12SiteVisitIdentityModels
            + [WizardState.self, CalendarMirrorMap.self]
    }
}
