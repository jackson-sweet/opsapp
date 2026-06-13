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
    /// Controlled via UserDefaults key "feature.useDataActor". Default: true.
    ///
    /// Verified on iPhone device 2026-04-19:
    ///   - Actor path engages from first sync trigger
    ///   - No crashes or "Unbinding from main queue" warnings
    ///   - @Query lists auto-refresh on iOS 26 (FB14750050 appears fixed; the
    ///     MainContextRefreshBridge is retained as cheap insurance)
    ///   - Marginal small-scale overhead on calendar week swipes; expected cost,
    ///     the mid-size-customer benefit is the design target
    ///
    /// Rollback: `UserDefaults.standard.set(false, forKey: "feature.useDataActor")`
    /// then force-quit + relaunch. Legacy @MainActor sync paths remain intact.
    static var useDataActor: Bool {
        UserDefaults.standard.object(forKey: "feature.useDataActor") as? Bool ?? true
    }

    /// Routes onboarding through the rebuilt flow (OnboardingFlowCoordinator +
    /// OnboardingGateway) instead of the legacy A/B-test coordinator. Rollout
    /// gate for the onboarding rebuild — **DEFAULT TRUE (cutover 2026-06-13)**:
    /// the rebuilt flow is now the shipping default. The legacy A/B coordinator
    /// and its screens remain in the codebase (dead while this is true) until the
    /// legacy-deletion pass; flip this back to false to instantly revert to the
    /// legacy router (still byte-identical when off). Controlled via UserDefaults
    /// key "feature.useRebuiltOnboarding".
    ///
    /// Disable (revert to legacy): `UserDefaults.standard.set(false, forKey: "feature.useRebuiltOnboarding")`
    /// then force-quit + relaunch.
    static var useRebuiltOnboarding: Bool {
        UserDefaults.standard.object(forKey: "feature.useRebuiltOnboarding") as? Bool ?? true
    }
}
