//
//  OPSSchemaV6.swift
//  OPS
//
//  Schema version 6.0.0 — Cashflow Forecast.
//
//  V6 adds two new SwiftData entities used by the Cashflow Forecast feature:
//   • `PaymentMilestone` — iOS parity for the existing server `payment_milestones`
//     table (was Supabase-only until this version). Read-side only in v1.
//   • `RecurringExpense` — owner-managed recurring outflows (rent, insurance,
//     payroll, subscriptions). Drives the recurring layer of the forecast.
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
            + OPSSchemaCommon.v3CatalogModels
            + OPSSchemaCommon.v4ReminderModels
            + OPSSchemaCommon.v6ForecastModels
            + [WizardState.self, CalendarMirrorMap.self]
    }
}
