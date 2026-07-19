//
//  OPSSchemaV18.swift
//  OPS
//
//  Schema version 18.0.0 — guarded lead assignment concurrency + chase columns.
//
//  Opportunity gains the required, zero-default Int64 `assignmentVersion`
//  snapshot (guarded assignment / conversion RPC concurrency) and three
//  optional Leads-chase fields: `handledAt` (operator's "handled — their
//  move" declaration), `aiSummary`, and `aiSummaryUpdatedAt`. V16–V17 retain
//  the frozen pre-widening shape (`OPSSchemaLegacyOpportunityV17`) so stores
//  created by released binaries remain recognizable. The live model begins
//  here, making the change an adjacent lightweight migration: the snapshot
//  defaults to zero and the chase columns default to nil for historical rows.
//

import Foundation
import SwiftData

enum OPSSchemaV18: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(18, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v18OpportunityModel
            + OPSSchemaCommon.v16DeckDesignModel
            + OPSSchemaCommon.v13ProjectNoteModel
            + OPSSchemaCommon.v15PhotoAnnotationModel
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
