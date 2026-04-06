//
//  FeatureFlagService.swift
//  OPS
//
//  Fetches feature flags and per-user overrides from Supabase.
//  Returns blocked permissions AND disabled flag slugs.
//  Fails closed: if the fetch fails, all known flags are treated as disabled.
//

import Foundation

/// Result of fetching feature flags — blocked permissions + disabled flag slugs.
struct FeatureFlagResult {
    let blockedPermissions: Set<String>
    let disabledFlags: Set<String>
}

enum FeatureFlagService {

    // MARK: - DTOs

    private struct FlagRow: Decodable {
        let slug: String
        let enabled: Bool
        let permissions: [String]?
    }

    private struct OverrideRow: Decodable {
        let flag_slug: String
    }

    // MARK: - Static Fallback Definitions (fail-closed)

    /// Hardcoded flag → permission mappings used when the fetch fails.
    /// Must be kept in sync with the feature_flags table.
    static let staticFlagDefinitions: [String: [String]] = [
        "pipeline": [
            "pipeline.view",
            "pipeline.manage",
            "pipeline.configure_stages"
        ],
        "estimates": [
            "estimates.create",
            "estimates.edit",
            "estimates.view"
        ],
        "accounting": [
            "accounting.view",
            "accounting.manage_connections",
            "portal.manage_branding",
            "portal.view",
            "documents.view",
            "documents.manage_templates"
        ],
        "deck_builder": [
            "deck_builder.view",
            "deck_builder.create",
            "deck_builder.edit"
        ]
    ]

    // MARK: - Fetch

    /// Fetch all feature flags and the user's overrides.
    /// Returns both blocked permissions and disabled flag slugs.
    static func fetchFlags(userId: String) async -> FeatureFlagResult {
        do {
            let client = SupabaseService.shared.client

            // 1. Fetch all feature flags
            let flags: [FlagRow] = try await client
                .from("feature_flags")
                .select("slug, enabled, permissions")
                .execute()
                .value

            // 2. Fetch this user's overrides (early-access grants)
            let overrides: [OverrideRow] = try await client
                .from("feature_flag_overrides")
                .select("flag_slug")
                .eq("user_id", value: userId)
                .execute()
                .value

            let overrideSlugs = Set(overrides.map(\.flag_slug))

            // 3. Build blocked permission set and disabled flag set
            var blocked = Set<String>()
            var disabled = Set<String>()

            for flag in flags {
                let isAccessible = flag.enabled || overrideSlugs.contains(flag.slug)
                if !isAccessible {
                    disabled.insert(flag.slug)
                    for perm in (flag.permissions ?? []) {
                        blocked.insert(perm)
                    }
                }
            }

            print("[FEATURE_FLAGS] Fetched \(flags.count) flags, \(overrides.count) overrides → \(disabled.count) disabled, \(blocked.count) permissions blocked")
            return FeatureFlagResult(blockedPermissions: blocked, disabledFlags: disabled)

        } catch {
            // Fail closed: treat ALL known flags as disabled
            print("[FEATURE_FLAGS] Fetch failed, failing closed: \(error)")
            return failClosedResult()
        }
    }

    /// Returns fail-closed result using static definitions (all flags disabled).
    static func failClosedResult() -> FeatureFlagResult {
        var blocked = Set<String>()
        var disabled = Set<String>()
        for (slug, perms) in staticFlagDefinitions {
            disabled.insert(slug)
            blocked.formUnion(perms)
        }
        return FeatureFlagResult(blockedPermissions: blocked, disabledFlags: disabled)
    }

    /// Convenience: just the blocked permission set for fail-closed.
    static func failClosedBlockedSet() -> Set<String> {
        return failClosedResult().blockedPermissions
    }
}
