//
//  FeatureFlags.swift
//  OPS
//
//  Lightweight feature flag container for staged rollouts.
//

import Foundation

enum FeatureFlags {
    /// Routes all sync-layer SwiftData writes through DataActor (background context)
    /// instead of the main context. Rollout gate for the ModelActor refactor Phase 1.
    /// Controlled via UserDefaults key "feature.useDataActor". Default: false.
    static var useDataActor: Bool {
        UserDefaults.standard.object(forKey: "feature.useDataActor") as? Bool ?? false
    }
}
