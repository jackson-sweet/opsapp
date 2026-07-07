//
//  OPSSchemaV14.swift
//  OPS
//
//  Schema version 14.0.0 — Unified activity parents.
//
//  V14 widens the `Activity` model so a timeline activity can be parented to a
//  lead (opportunity), a client, OR a job (project), and can carry an author:
//    • `opportunityId` relaxes from a required `String` to an optional `String?`
//      (an activity no longer has to hang off an opportunity).
//    • `clientId` and `projectId` are added (nullable) so the same activity
//      table serves client- and job-scoped timelines.
//  This mirrors the shipped multi-parent `FollowUp` precedent.
//
//  `Activity` shipped through V1–V13 inside the frozen pre-widening shape, so
//  widening it in place would shift EVERY historical schema's fingerprint by
//  the same delta — the hazard documented in `OPSApp.swift`. Following the
//  `SiteVisit` V10→V11 precedent exactly, the pre-widening shape is frozen as
//  `OPSSchemaLegacyActivity.Activity` and backs V1–V13 (`v1ToV12ActivityModel`);
//  the live widened `Activity` backs V14+ (`v13ActivityModel`). Because the two
//  Activity shapes differ by real persistent attributes, V14's checksum diverges
//  from V13 organically — the same "mint a real new-shape model" discipline that
//  V6 (forecast models) and V11 (optional SiteVisit) used.
//
//  Purely additive at the SQLite level — `opportunity_id` required→optional and
//  two new nullable columns. No rename, retype-to-narrower, or drop. SwiftData
//  lightweight migration handles the on-disk V13 store transparently: existing
//  non-null `opportunityId` values are preserved and the new columns default to
//  nil for historical rows.
//

import Foundation
import SwiftData

enum OPSSchemaV14: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(14, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v13ProjectNoteModel
            + OPSSchemaCommon.v13ActivityModel
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
