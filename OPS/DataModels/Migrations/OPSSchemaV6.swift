//
//  OPSSchemaV6.swift
//  OPS
//
//  Schema version 6.0.0 — Dimensioned Photo Deliverables.
//
//  V6 adds `PhotoAnnotation.renderedPhotoURL` — a derived 2048-long-edge PNG
//  deliverable with burned-in dimensions, kept alongside the source HEIC.
//  Purely additive (nullable scalar). SwiftData lightweight migration handles
//  the V5 store transparently because no existing column is renamed, retyped,
//  or made non-optional.
//
//  Reason the bump exists: V4 and V5 both reference the live `PhotoAnnotation`
//  type via `OPSSchemaCommon.unchangedModels`. The moment a new persistent
//  property landed on the live class (sibling commit 6b62f40 — "Persist
//  rendered dimensioned photo deliverables"), both V4 and V5 silently picked
//  it up and their migration-stage hashes collided, producing the
//  "Duplicate version checksums across stages detected" runtime crash at
//  ModelContainer init. The fix is to mint a new VersionedSchema that owns
//  the new property explicitly, append a `.lightweight` V5 → V6 stage, and
//  bump `OPSApp.sharedModelContainer` to declare V6 as the latest. See the
//  comment block at the top of `OPSApp.swift` for the long-form playbook.
//

import Foundation
import SwiftData

enum OPSSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v3CatalogModels
            + OPSSchemaCommon.v4ReminderModels
            + [WizardState.self, CalendarMirrorMap.self]
    }
}
