//
//  OPSSchemaV10.swift
//  OPS
//
//  Schema version 10.0.0 — Stock-unit lifecycle ledger.
//
//  V10 adds `CatalogStockUnitEvent`, the local mirror of the append-only
//  `catalog_stock_unit_events` table. It records the parentage trail behind
//  every stock unit (receive / consume / offcut_create / adjust / scrap), so
//  the vinyl deck-builder cut path can bank offcuts with a full audit trail and
//  offcut provenance (source roll ↔ offcut) resolves on every device.
//
//  Purely additive over V9 — no rename, retype, or drop. `CatalogStockUnitEvent`
//  is a brand-new @Model, so V10's persistent checksum diverges from V9
//  organically and SwiftData lightweight migration handles the on-disk V9 store
//  transparently.
//

import Foundation
import SwiftData

enum OPSSchemaV10: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(10, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v1ToV10SiteVisitModel
            + OPSSchemaCommon.v4CoreModels
            + OPSSchemaCommon.v4TaskModels
            + OPSSchemaCommon.v8CatalogModels
            + OPSSchemaCommon.v4ReminderModels
            + OPSSchemaCommon.v6ForecastModels
            + OPSSchemaCommon.v7VinylOrderModels
            + OPSSchemaCommon.v8CatalogSetupModels
            + OPSSchemaCommon.v9ProjectPhotoModels
            + OPSSchemaCommon.v10StockUnitEventModels
            + [WizardState.self, CalendarMirrorMap.self]
    }
}
