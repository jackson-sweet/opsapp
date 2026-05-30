//
//  OPSSchemaV2.swift
//  OPS
//
//  Current OPS SwiftData schema (version 2.0.0). Identical to V1 except
//  that `WizardState` gains an `@Attribute(.unique) var id: String` primary
//  key used by the Supabase sync layer to route rows unambiguously.
//

import Foundation
import SwiftData

enum OPSSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v1ToV3CoreModels
            + OPSSchemaCommon.v1ToV3TaskModels
            + OPSSchemaCommon.v2InventoryModels
            + [WizardState.self]
    }
}
