//
//  OPSSchemaV20.swift
//  OPS
//
//  Schema version 20.0.0 — per-message email identity on the activity feed.
//
//  `Activity` gains five nullable/defaulted attributes — `emailMessageId`,
//  `emailThreadId`, `fromEmail`, `toEmails`, `ccEmails` — the identity fields
//  the server has always written but the client dropped, which is why a lead's
//  activity feed read as an undifferentiated thread dump (bug 183f7ec9).
//
//  V14–V19 retain their frozen released shape (`OPSSchemaLegacyActivityV19`) so
//  installed stores stay recognizable; the widened live `Activity` begins here.
//  Historical rows receive nil / empty arrays through an adjacent lightweight
//  migration.
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
            + OPSSchemaCommon.v20ActivityModel
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
