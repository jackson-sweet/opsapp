//
//  OPSSchemaV13.swift
//  OPS
//
//  Schema version 13.0.0 — project-note system events.
//
//  Adds two optional columns to `ProjectNote` mirroring the live Supabase
//  `project_notes` shape: `eventKind` (system-event discriminator — web writes
//  `status_change`, iOS writes `site_visit` for the packet entry) and
//  `contentMetadataJSON` (raw jsonb payload for structured system entries).
//  Purely additive optional attributes — a lightweight transform.
//
//  `Activity` and `SiteVisit` are unchanged at this boundary: Activity is still
//  the pre-widening (narrow, required-opportunityId) shape frozen as
//  `v1ToV12ActivityModel` — the unified-activity widening lands at V14 — and
//  SiteVisit is the optional-opportunityId shape (`v11SiteVisitModel`); its
//  `loggedActivityId` widening lands at V15.
//

import Foundation
import SwiftData

enum OPSSchemaV13: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(13, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v1ToV15OpportunityModel
            + OPSSchemaCommon.v1ToV15DeckDesignModel
            + OPSSchemaCommon.v13ProjectNoteModel
            + OPSSchemaCommon.v1ToV14PhotoAnnotationModel
            + OPSSchemaCommon.v1ToV12ActivityModel
            + OPSSchemaCommon.v11SiteVisitModel
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
