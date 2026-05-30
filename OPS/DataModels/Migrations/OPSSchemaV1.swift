//
//  OPSSchemaV1.swift
//  OPS
//
//  Legacy SwiftData schema (version 1.0.0) — the shape that shipped before
//  `WizardState.id` was added for the Supabase sync contract.
//
//  V1 uses frozen legacy core/task models plus the original WizardState shape
//  so SwiftData can reproduce the historical model graph exactly. Referencing
//  current top-level models here can collapse staged-migration fingerprints
//  after later relationship changes.
//

import Foundation
import SwiftData

enum OPSSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
            + OPSSchemaCommon.v1ToV3CoreModels
            + OPSSchemaCommon.v1ToV3TaskModels
            + [OPSSchemaV1.WizardState.self]
    }

    /// Legacy WizardState shape — identical to the original commit
    /// (`89dfbd5 feat: add guided wizard system …`) before the `id` attribute
    /// was introduced for the sync layer. Keeping this declaration alive is
    /// what lets SwiftData open pre-migration stores without crashing.
    @Model
    final class WizardState {
        var wizardId: String
        var statusRaw: String
        var currentStepIndex: Int
        var doNotShow: Bool
        var completedAt: Date?
        var totalDurationMs: Int
        var stepsSkipped: Int
        var lastActiveAt: Date?
        var currentSessionId: String
        var userId: String
        var needsSync: Bool
        var lastSyncedAt: Date?

        init(wizardId: String, userId: String) {
            self.wizardId = wizardId
            self.userId = userId
            self.statusRaw = "not_started"
            self.currentStepIndex = 0
            self.doNotShow = false
            self.completedAt = nil
            self.totalDurationMs = 0
            self.stepsSkipped = 0
            self.lastActiveAt = nil
            self.currentSessionId = UUID().uuidString
            self.needsSync = false
            self.lastSyncedAt = nil
        }
    }
}
