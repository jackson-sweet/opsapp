//
//  OnboardingVariantManager.swift
//  OPS
//
//  Manages A/B/C test variant assignment for onboarding flows.
//  Fetches variant from Firebase Remote Config on first launch,
//  caches to UserDefaults so it never changes for a given user.
//

import Foundation
import FirebaseRemoteConfig

// MARK: - Variant Enum

/// The three onboarding flow variants under test
enum OnboardingVariant: String, CaseIterable {
    case A = "A"
    case B = "B"
    case C = "C"
}

// MARK: - Variant Manager

@MainActor
final class OnboardingVariantManager: ObservableObject {

    static let shared = OnboardingVariantManager()

    /// The resolved onboarding variant for this user
    @Published private(set) var variant: OnboardingVariant = .A

    /// Whether the variant has been resolved (from cache or Remote Config)
    @Published private(set) var isReady: Bool = false

    private let userDefaultsKey = "onboarding_variant"
    private let remoteConfigKey = "onboarding_variant"

    private init() {
        // Check for a cached variant from a previous launch
        if let cached = UserDefaults.standard.string(forKey: userDefaultsKey),
           let cachedVariant = OnboardingVariant(rawValue: cached) {
            self.variant = cachedVariant
            self.isReady = true
            print("[VARIANT] Loaded cached variant: \(cachedVariant.rawValue)")
        } else {
            print("[VARIANT] No cached variant found, will fetch from Remote Config")
        }
    }

    // MARK: - Fetch

    /// Fetches the variant from Firebase Remote Config if not already resolved.
    /// On failure, defaults to variant A and caches the result.
    func fetchVariant() async {
        guard !isReady else {
            print("[VARIANT] Already resolved, skipping fetch")
            return
        }

        let remoteConfig = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()

        #if DEBUG
        settings.minimumFetchInterval = 0
        print("[VARIANT] Debug build — minimumFetchInterval = 0")
        #else
        settings.minimumFetchInterval = 3600
        #endif

        remoteConfig.configSettings = settings

        // Set default value so we always have a fallback
        remoteConfig.setDefaults([remoteConfigKey: "A" as NSObject])

        do {
            let status = try await remoteConfig.fetchAndActivate()
            let value = remoteConfig.configValue(forKey: remoteConfigKey).stringValue ?? "A"
            let resolved = OnboardingVariant(rawValue: value) ?? .A

            print("[VARIANT] Remote Config status: \(status.rawValue), value: \"\(value)\", resolved: \(resolved.rawValue)")

            cacheAndApply(resolved)
        } catch {
            print("[VARIANT] Remote Config fetch failed: \(error.localizedDescription). Defaulting to A")
            cacheAndApply(.A)
        }
    }

    // MARK: - Override (Debug / Testing)

    /// Force a specific variant. Caches the override so it persists.
    func overrideVariant(_ newVariant: OnboardingVariant) {
        print("[VARIANT] Override to \(newVariant.rawValue)")
        cacheAndApply(newVariant)
    }

    // MARK: - Private

    private func cacheAndApply(_ resolved: OnboardingVariant) {
        UserDefaults.standard.set(resolved.rawValue, forKey: userDefaultsKey)
        variant = resolved
        isReady = true
        print("[VARIANT] Cached and applied variant: \(resolved.rawValue)")
    }
}
