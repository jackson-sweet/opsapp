//
//  OPSSchemaV22.swift
//  OPS
//
//  Schema version 22.0.0 — the site-visit link on the activity feed.
//
//  `Activity` gains one nullable attribute, `siteVisitId`. iOS has always
//  WRITTEN `activities.site_visit_id` when a visit completes
//  (`ActivityRepository.logActivity(siteVisitId:)`) but never decoded it back,
//  so a completed site visit reached the lead's timeline as an unremarkable
//  row with no route to what the visit actually captured.
//
//  V14–V20 retain `OPSSchemaLegacyActivityV19` and V21 retains
//  `OPSSchemaLegacyActivityV21`, so installed stores stay recognizable and
//  every released fingerprint stays exact; the widened live `Activity` begins
//  here. Site-visit models carry forward unchanged from the V20 cloud schema.
//  Historical rows receive nil through an adjacent lightweight migration.
//

import Foundation
import SwiftData

enum OPSSchemaV22: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(22, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v19OpportunityModel
            + OPSSchemaCommon.v16DeckDesignModel
            + OPSSchemaCommon.v13ProjectNoteModel
            + OPSSchemaCommon.v18PhotoAnnotationModel
            + OPSSchemaCommon.v22ActivityModel
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
