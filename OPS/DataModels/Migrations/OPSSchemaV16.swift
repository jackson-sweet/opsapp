//
//  OPSSchemaV16.swift
//  OPS
//
//  Schema version 16.0.0 — guarded lead assignment concurrency.
//
//  Opportunity gains one required Int64 assignmentVersion attribute with a
//  zero default. The V1-V15 shape is frozen separately, so this additive
//  lightweight boundary changes only V16's persistent fingerprint and keeps
//  every shipped historical schema exact.
//

import Foundation
import SwiftData

enum OPSSchemaV16: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(16, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v16OpportunityModel
            + OPSSchemaCommon.v13ProjectNoteModel
            + OPSSchemaCommon.v15PhotoAnnotationModel
            + OPSSchemaCommon.v13ActivityModel
            + OPSSchemaCommon.v14SiteVisitModel
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
            + OPSSchemaCommon.v12SiteVisitIdentityModels
            + [WizardState.self, CalendarMirrorMap.self]
    }
}
