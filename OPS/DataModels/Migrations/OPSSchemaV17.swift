//
//  OPSSchemaV17.swift
//  OPS
//
//  Schema version 17.0.0 — vinyl order marker gains color + PO.
//
//  V17 widens the local `ProjectVinylOrderMarker` projection with two nullable
//  fields, `vinylColor` and `vinylPO`, mirroring the additive
//  `projects.vinyl_color` / `vinyl_po` columns that back the VINYL ORDERS
//  board (2026-07-16). V7–V16 retain the frozen pre-widening marker shape
//  (`OPSSchemaLegacyVinylOrderV16`) so stores created by released binaries
//  remain recognizable. The live widened marker begins here, making the change
//  an adjacent lightweight migration: both new columns default to nil for
//  historical rows.
//

import Foundation
import SwiftData

enum OPSSchemaV17: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(17, 0, 0) }

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
            + OPSSchemaCommon.v17VinylOrderModel
            + OPSSchemaCommon.v8CatalogSetupModels
            + OPSSchemaCommon.v9ProjectPhotoModels
            + OPSSchemaCommon.v10StockUnitEventModels
            + OPSSchemaCommon.v11SiteVisitCaptureModels
            + OPSSchemaCommon.v12SiteVisitIdentityModels
            + [WizardState.self, CalendarMirrorMap.self]
    }
}
