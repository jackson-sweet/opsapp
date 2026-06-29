//
//  OPSSchemaV3.swift
//  OPS
//
//  Schema version 3.0.0 — Catalog & Variant Model.
//  V3 drops InventoryItem/InventoryTag/InventoryUnit/InventorySnapshot/
//  InventorySnapshotItem and adds the catalog_* and product_* extension
//  entities. WizardState is unchanged from V2.
//

import Foundation
import SwiftData

enum OPSSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v1ToV10SiteVisitModel
            + OPSSchemaCommon.v1ToV3CoreModels
            + OPSSchemaCommon.v1ToV3TaskModels
            + OPSSchemaCommon.v3CatalogModels
            + [WizardState.self]
    }
}
