//
//  OPSSchemaV21.swift
//  OPS
//
//  Schema version 21.0.0 — the site-visit link on the activity feed.
//
//  `Activity` gains one nullable attribute, `siteVisitId`. iOS has always
//  WRITTEN `activities.site_visit_id` when a visit completes
//  (`ActivityRepository.logActivity(siteVisitId:)`) but never decoded it back,
//  so a completed site visit reached the lead's timeline as an unremarkable
//  row with no route to what the visit actually captured.
//
//  V14–V19 retain `OPSSchemaLegacyActivityV19` and V20 retains
//  `OPSSchemaLegacyActivityV20`, so installed stores stay recognizable and
//  every released fingerprint stays exact; the widened live `Activity` begins
//  here. Historical rows receive nil through an adjacent lightweight migration.
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
