//
//  OPSSchemaV20.swift
//  OPS
//
//  Schema version 20.0.0 — cloud-backed site-visit packets.
//
//  SiteVisit gains the complete server projection plus sync bookkeeping, and
//  SiteVisitIdentityDraft gains cloud deletion/sync state. V19 retains frozen
//  released shapes so installed stores migrate through one additive boundary.
//

import Foundation
import SwiftData

enum OPSSchemaV20: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(20, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v19OpportunityModel
            + OPSSchemaCommon.v16DeckDesignModel
            + OPSSchemaCommon.v13ProjectNoteModel
            + OPSSchemaCommon.v18PhotoAnnotationModel
            + OPSSchemaCommon.v13ActivityModel
            + OPSSchemaCommon.v20SiteVisitModel
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
