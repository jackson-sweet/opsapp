//
//  OPSSchemaV6.swift
//  OPS
//
//  Schema version 6.0.0 — Cashflow Forecast (with consolidated PhotoAnnotation
//  rendered-deliverable parity).
//
//  V6 adds two new SwiftData entities used by the Cashflow Forecast feature:
//   • `PaymentMilestone` — iOS parity for the existing server `payment_milestones`
//     table (was Supabase-only until this version). Read-side only in v1; estimate
//     form writes via `EstimateService` payload.
//   • `RecurringExpense` — owner-managed recurring outflows (rent, insurance,
//     payroll, subscriptions). Drives the recurring layer of the forecast.
//  These two new model types are the *real* checksum differentiator vs V5 — V6's
//  hash diverges from V5 organically because `v6ForecastModels` is appended.
//
//  V6 also implicitly absorbs the `PhotoAnnotation.renderedPhotoURL` property
//  added by ops-ios commit 6b62f40 ("Persist rendered dimensioned photo
//  deliverables"). That property lives on the live `PhotoAnnotation` class which
//  is referenced by every historical schema via `OPSSchemaCommon.unchangedModels`
//  — when a persistent property lands on a live `@Model` like that, every
//  schema's hash shifts by the same delta, so the relative distinctness between
//  schemas is preserved. The crash that surfaced on `main` before this merge
//  ("Duplicate version checksums across stages detected") came from minting a
//  V6 whose models list was *identical* to V5 — collapsing the stage chain. The
//  fix is exactly this V6 — a V6 with at least one real new model so it differs
//  from V5 by design, not by accident.
//
//  Purely additive over V5 — no rename, retype, or drop. SwiftData lightweight
//  migration handles the schema diff transparently.
//
//  See docs/superpowers/specs/2026-05-11-cashflow-forecast-design.md and
//  ops-software-bible/09_FINANCIAL_SYSTEM.md § Cashflow Forecast.
//

import Foundation
import SwiftData

enum OPSSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v4CoreModels
            + OPSSchemaCommon.v4TaskModels
            + OPSSchemaCommon.v3CatalogModels
            + OPSSchemaCommon.v4ReminderModels
            + OPSSchemaCommon.v6ForecastModels
            + [WizardState.self, CalendarMirrorMap.self]
    }
}

/// Schema version 7.0.0 — Project-level Vinyl Order marker.
///
/// V7 adds `ProjectVinylOrderMarker`, a local projection of the
/// `projects.vinyl_order_*` server fields. It is intentionally separate from
/// `Project` so this additive feature has a real schema differentiator without
/// mutating the historical Project model used by older versioned schemas.
enum OPSSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(7, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v4CoreModels
            + OPSSchemaCommon.v4TaskModels
            + OPSSchemaCommon.v3CatalogModels
            + OPSSchemaCommon.v4ReminderModels
            + OPSSchemaCommon.v6ForecastModels
            + OPSSchemaCommon.v7VinylOrderModels
            + [WizardState.self, CalendarMirrorMap.self]
    }
}

/// Schema version 8.0.0 — Catalog setup data foundation.
///
/// V8 adds physical catalog stock units plus product↔catalog option mappings.
/// It is also the first schema stage to use the live top-level
/// `ProductBundleItem` shape with relationship fields. V3-V7 keep a frozen
/// legacy ProductBundleItem model so their schema fingerprints stay stable.
enum OPSSchemaV8: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(8, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v4CoreModels
            + OPSSchemaCommon.v4TaskModels
            + OPSSchemaCommon.v8CatalogModels
            + OPSSchemaCommon.v4ReminderModels
            + OPSSchemaCommon.v6ForecastModels
            + OPSSchemaCommon.v7VinylOrderModels
            + OPSSchemaCommon.v8CatalogSetupModels
            + [WizardState.self, CalendarMirrorMap.self]
    }
}
