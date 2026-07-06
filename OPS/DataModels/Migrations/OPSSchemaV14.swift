//
//  OPSSchemaV14.swift
//  OPS
//
//  Schema version 14.0.0 — site-visit → timeline auto-post idempotency.
//
//  V14 widens the local-only `SiteVisit` model with a single nullable field,
//  `loggedActivityId`. When a completed site visit posts its "Site visit" row
//  to the `activities` timeline (app-side, because `SiteVisit` never syncs to
//  Supabase), the returned activity id is stamped here so re-completing the
//  visit — e.g. an offline retry — cannot post a duplicate.
//
//  `SiteVisit` shipped through V11–V13 inside `v11SiteVisitModel`, so widening
//  it in place would shift EVERY V11–V13 schema's fingerprint by the same delta
//  — the hazard documented in `OPSApp.swift`. Following the V10→V11 (optional
//  opportunityId) and V12→V13 (Activity parents) precedents exactly, the
//  pre-widening shape is frozen as `OPSSchemaLegacySiteVisitV11.SiteVisit` and
//  backs V11–V13 (`v11SiteVisitModel`); the live widened `SiteVisit` backs V14+
//  (`v14SiteVisitModel`). Because the two shapes differ by a real persistent
//  attribute, V14's checksum diverges from V13 organically.
//
//  Purely additive at the SQLite level — one new nullable column. No rename,
//  retype, or drop. SwiftData lightweight migration handles the on-disk V13
//  store transparently: the new column defaults to nil for historical rows.
//

import Foundation
import SwiftData

enum OPSSchemaV14: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(14, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
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
