//
//  OPSSchemaV3.swift
//  OPS
//
//  Schema version 3.0.0. Additive over V2: adds `CalendarMirrorMap`, the
//  client-local side-table powering the iPhone Calendar Mirror feature.
//  No existing model shape changes — lightweight migration from V2.
//

import Foundation
import SwiftData

enum OPSSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels + [WizardState.self, CalendarMirrorMap.self]
    }
}
