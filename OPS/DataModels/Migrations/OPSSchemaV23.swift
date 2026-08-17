//
//  OPSSchemaV23.swift
//  OPS
//
//  Schema version 23.0.0 — site-visit booking fields.
//
//  `SiteVisit` gains two nullable server-owned attributes: `bookedAt` (the
//  booking discriminator mirroring `site_visits.booked_at`) and
//  `reminderLeadMinutes` (the per-booking heads-up override). The booking
//  build originally widened the live class in place, which silently shifted
//  the V20–V22 fingerprints and made every installed store unrecognizable at
//  launch (CoreData 134504 on device, 2026-08-17). V20–V22 now retain
//  `OPSSchemaLegacySiteVisitV22`, so every released fingerprint stays exact;
//  the widened live `SiteVisit` begins here. Historical rows receive nil for
//  both fields through an adjacent lightweight migration.
//

import Foundation
import SwiftData

enum OPSSchemaV23: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(23, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v19OpportunityModel
            + OPSSchemaCommon.v16DeckDesignModel
            + OPSSchemaCommon.v13ProjectNoteModel
            + OPSSchemaCommon.v18PhotoAnnotationModel
            + OPSSchemaCommon.v22ActivityModel
            + OPSSchemaCommon.v23SiteVisitModel
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
