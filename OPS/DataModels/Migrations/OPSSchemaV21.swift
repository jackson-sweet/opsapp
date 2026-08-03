//
//  OPSSchemaV21.swift
//  OPS
//
//  Schema version 21.0.0 — per-message email identity on the activity feed.
//
//  `Activity` gains five nullable/defaulted attributes — `emailMessageId`,
//  `emailThreadId`, `fromEmail`, `toEmails`, `ccEmails` — the identity fields
//  the server has always written but the client dropped, which is why a lead's
//  activity feed read as an undifferentiated thread dump (bug 183f7ec9).
//
//  V14–V20 retain their frozen released `Activity` shape
//  (`OPSSchemaLegacyActivityV19`) so installed stores stay recognizable, and the
//  widened `Activity` graph begins here. It is itself frozen as
//  `OPSSchemaLegacyActivityV21` because V22 widens the live model again with the
//  site-visit link. Site-visit models carry forward unchanged from the V20 cloud
//  schema. Historical rows receive nil / empty arrays through an adjacent
//  lightweight migration.
//

import Foundation
import SwiftData

enum OPSSchemaV21: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(21, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v19OpportunityModel
            + OPSSchemaCommon.v16DeckDesignModel
            + OPSSchemaCommon.v13ProjectNoteModel
            + OPSSchemaCommon.v18PhotoAnnotationModel
            + OPSSchemaCommon.v21ActivityModel
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
